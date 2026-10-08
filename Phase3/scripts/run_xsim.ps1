param([string]$VivadoRoot='D:/Application/Xilinx/Vivado/2020.2')
$ErrorActionPreference='Stop'
$phaseRoot=Split-Path -Parent $PSScriptRoot
$simRoot=Join-Path $phaseRoot 'build/direct_sim'
New-Item -ItemType Directory -Force -Path $simRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $VivadoRoot 'data/xsim/xsim.ini') -Destination $simRoot -Force
Copy-Item -Path (Join-Path $phaseRoot 'build/fixtures/*.hex') -Destination $simRoot -Force
Push-Location -LiteralPath $simRoot
try {
    & "$VivadoRoot/bin/xvlog.bat" --sv --work xil_defaultlib -i "$phaseRoot/build/fixtures" "$phaseRoot/rtl/phase3_fft_top.sv" "$phaseRoot/sim/tb_phase3_fft.sv"
    if($LASTEXITCODE -ne 0){throw 'SV compile failed'}
    & "$VivadoRoot/bin/xvhdl.bat" --work xil_defaultlib "$phaseRoot/build/vivado/phase3_fft.gen/sources_1/ip/fft2048/sim/fft2048.vhd"
    if($LASTEXITCODE -ne 0){throw 'IP wrapper compile failed'}
    & "$VivadoRoot/bin/xelab.bat" --debug typical --relax -L xil_defaultlib -L xfft_v9_1_5 -L secureip --snapshot phase3_sim xil_defaultlib.tb_phase3_fft
    if($LASTEXITCODE -ne 0){throw 'Elaboration failed'}
    & "$VivadoRoot/bin/xsim.bat" phase3_sim --runall --log fft_sim.log
    if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
    $simText=Get-Content -LiteralPath fft_sim.log -Raw
    if($simText -notmatch 'PHASE3_FFT_PASS' -or $simText -match 'Fatal:|Error:'){throw 'FFT assertions failed'}
    Copy-Item -LiteralPath fft_sim.log,nine_bins.csv -Destination "$phaseRoot/build/reports" -Force
} finally {Pop-Location}
