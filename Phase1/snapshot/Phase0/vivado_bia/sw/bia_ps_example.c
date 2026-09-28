/* Vitis bare-metal BSP example. Add xil, axidma, math (-lm) libraries.
 * Board DDR/MIO settings, generated xparameters.h and DMA instance are supplied
 * by your actual hardware design. This file was not compiled against a board BSP.
 */
#include "xil_io.h"
#include "xil_cache.h"
#include "xaxidma.h"
#include "xtime_l.h"
#include <stdint.h>
#include <math.h>
#include <stddef.h>

#define BIA_N 16384u
#define BIA_RAW_BYTES (64u + 4u*BIA_N + 16u)
#define BIA_DFT_BYTES (64u + 8u*32u + 16u)
#define BIA_INVALID_MASK 0x4fu
static uint8_t rx_buffer[131072] __attribute__((aligned(64)));
static double waveform[BIA_N];

typedef struct { double re, im; } bia_complex;

/* Load only an idle/inactive bank. peak_code is DAC code amplitude, NOT mA. */
int bia_load_wave(UINTPTR base, unsigned bank, const unsigned freq_bin[8],
                  unsigned peak_code) {
    double peak=0;
    unsigned n,k;
    if(bank>1 || peak_code>32767 || peak_code==0) return -1;
    /* This simple helper intentionally loads only when all acquisition is idle. */
    if(Xil_In32(base+0x08)&1u) return -2;
    for(k=0;k<8;k++) if(freq_bin[k]==0 || freq_bin[k]>=BIA_N/2) return -3;
    for(n=0;n<BIA_N;n++) {
        double x=0;
        for(k=0;k<8;k++) {
            double phase=-3.141592653589793*(double)k*(double)((int)k-1)/8.0;
            x+=sin(6.283185307179586*(double)freq_bin[k]*n/BIA_N+phase);
        }
        waveform[n]=x;
        if(fabs(x)>peak) peak=fabs(x);
    }
    for(n=0;n<BIA_N;n++) {
        int code=32768+(int)lround(waveform[n]*(double)peak_code/peak);
        Xil_Out32(base+(bank ? 0x20000u:0x10000u)+4u*n,(uint32_t)code);
    }
    return 0;
}

/* Caller initializes XAxiDma using its BSP device ID before invoking this.
 * raw_mode=1 uploads samples; raw_mode=0 uploads eight complex V/I pairs.
 * ADC hardware must be configured in offset-binary mode for option bit 2=1.
 * Repeated measurements: call again with incremented frame_id, using two owned
 * DDR buffers / SG DMA when extending to pipelined software processing.
 */
int bia_run_frame(UINTPTR base, XAxiDma *dma, uint32_t session_id,
                  uint32_t frame_id, uint32_t config_id, uint32_t fs_hz,
                  uint32_t electrode_map, unsigned bank, unsigned raw_mode,
                  uint32_t settle_cycles, const unsigned freq_bin[8],
                  const uint32_t **packet, size_t *packet_bytes) {
    XTime begin,now;
    uint32_t bytes=raw_mode ? BIA_RAW_BYTES:BIA_DFT_BYTES;
    uint32_t cache_bytes=(bytes+63u)&~63u;
    uint32_t *words=(uint32_t*)rx_buffer;
    unsigned k;
    if(bank>1 || raw_mode>1 || fs_hz==0) return -1;
    if(Xil_In32(base)!=0x31414942u || Xil_In32(base+0x2c)!=BIA_N) return -2;
    if((Xil_In32(base+0x08)&1u) || XAxiDma_Busy(dma,XAXIDMA_DEVICE_TO_DMA)) return -3;
    if(XAxiDma_HasSg(dma)) return -4; /* this example uses Simple DMA */
    for(k=0;k<8;k++) {
        unsigned j;
        if(freq_bin[k]==0 || freq_bin[k]>=BIA_N/2) return -5;
        for(j=0;j<k;j++) if(freq_bin[k]==freq_bin[j]) return -5;
    }
    Xil_Out32(base+0x0c,session_id); Xil_Out32(base+0x10,frame_id);
    Xil_Out32(base+0x14,config_id); Xil_Out32(base+0x18,fs_hz);
    Xil_Out32(base+0x1c,settle_cycles); Xil_Out32(base+0x20,16);
    Xil_Out32(base+0x24,electrode_map&0xfffffu);
    Xil_Out32(base+0x28,bank|(raw_mode<<1)|4u);
    for(k=0;k<8;k++) Xil_Out32(base+0x40+4*k,freq_bin[k]);
    /* RX buffer owns complete cache lines; CPU must not touch it during DMA. */
    Xil_DCacheFlushRange((INTPTR)rx_buffer,cache_bytes);
    if(XAxiDma_SimpleTransfer(dma,(UINTPTR)rx_buffer,bytes,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
        return -6;
    Xil_Out32(base+0x04,1); /* ARM DMA FIRST, then start PL acquisition. */
    XTime_GetTime(&begin);
    while(XAxiDma_Busy(dma,XAXIDMA_DEVICE_TO_DMA)) {
        uint32_t ds=XAxiDma_ReadReg(dma->RegBase,XAXIDMA_RX_OFFSET+XAXIDMA_SR_OFFSET);
        if(ds&XAXIDMA_ERR_ALL_MASK) return -7;
        XTime_GetTime(&now);
        if(now-begin>2u*(uint64_t)COUNTS_PER_SECOND) return -8;
        /* On timeout/error, use the board's reset/fault procedure before retry.
         * Do not reuse this buffer while any DMA transfer remains active. */
    }
    Xil_DCacheInvalidateRange((INTPTR)rx_buffer,cache_bytes);
    if(words[0]!=0x31414942u || words[3]!=frame_id || words[10]!=BIA_N) return -9;
    *packet=words; *packet_bytes=bytes;
    if(words[bytes/4-4]&BIA_INVALID_MASK) return -10;
    /* Status bit 4 remains set until physical timestamp delay is calibrated. */
    return 0;
}

static int64_t read_s64(const uint32_t *p) {
    return (int64_t)(((uint64_t)p[1]<<32)|(uint64_t)p[0]);
}

/* calibrated factor = Rsense * HI(f)/HV(f), complex, in ohms.
 * Neither Rsense nor channel gains are guessed from the schematic here.
 */
int bia_impedance(const uint32_t *packet,unsigned tone,bia_complex factor,
                   bia_complex *z) {
    const uint32_t *p;
    double vr,vi,ir,ii,den,rr,ri;
    if(tone>=8 || packet[0]!=0x31414942u || (packet[1]&1u)) return -1;
    if(packet[BIA_DFT_BYTES/4-4]&BIA_INVALID_MASK) return -2;
    p=packet+16+8*tone;
    vr=(double)read_s64(p); vi=(double)read_s64(p+2);
    ir=(double)read_s64(p+4); ii=(double)read_s64(p+6);
    den=ir*ir+ii*ii;
    if(den<1.0) return -3; /* application should set a measured noise threshold */
    rr=(vr*ir+vi*ii)/den; ri=(vi*ir-vr*ii)/den;
    z->re=factor.re*rr-factor.im*ri;
    z->im=factor.re*ri+factor.im*rr;
    return 0;
}
