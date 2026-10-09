param([string]$VivadoRoot='D:/Application/Xilinx/Vivado/2020.2')
$ErrorActionPreference='Stop'
$phaseRoot=Split-Path -Parent $PSScriptRoot
$simRoot=Join-Path $phaseRoot 'build/direct_sim'
New-Item -ItemType Directory -Force -Path $simRoot,"$phaseRoot/build/reports" | Out-Null
Copy-Item -LiteralPath (Join-Path $VivadoRoot 'data/xsim/xsim.ini') -Destination $simRoot -Force
Copy-Item -Path (Join-Path $phaseRoot 'build/fixtures/*.hex') -Destination $simRoot -Force
Push-Location -LiteralPath $simRoot
try {
    & "$VivadoRoot/bin/xvlog.bat" --sv --work xil_defaultlib "$phaseRoot/generated/electrode_map.sv" "$phaseRoot/rtl/phase5_scan_top.sv" "$phaseRoot/../Phase2/rtl/adc_frame_buffer.sv" "$phaseRoot/sim/tb_phase5_scan.sv"
    if($LASTEXITCODE -ne 0){throw 'Compile failed'}
    & "$VivadoRoot/bin/xelab.bat" --debug typical --snapshot phase5_sim xil_defaultlib.tb_phase5_scan
    if($LASTEXITCODE -ne 0){throw 'Elaboration failed'}
    & "$VivadoRoot/bin/xsim.bat" phase5_sim --runall --log scan_sim.log
    if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
    $simText=Get-Content -LiteralPath scan_sim.log -Raw
    if($simText -notmatch 'PHASE5_SCAN_PASS' -or $simText -match 'Fatal:|Error:'){throw 'Scan assertions failed'}
    Copy-Item -Path scan_sim.log,scan_*_trace.csv -Destination "$phaseRoot/build/reports" -Force
} finally {Pop-Location}
