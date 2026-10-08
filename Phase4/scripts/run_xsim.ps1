param([string]$VivadoRoot='D:/Application/Xilinx/Vivado/2020.2')
$ErrorActionPreference='Stop'
$phaseRoot=Split-Path -Parent $PSScriptRoot
$simRoot=Join-Path $phaseRoot 'build/direct_sim'
New-Item -ItemType Directory -Force -Path $simRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $VivadoRoot 'data/xsim/xsim.ini') -Destination $simRoot -Force
Copy-Item -Path (Join-Path $phaseRoot 'build/fixtures/*.hex') -Destination $simRoot -Force
Push-Location -LiteralPath $simRoot
try {
    & "$VivadoRoot/bin/xvlog.bat" --sv --work xil_defaultlib -i "$phaseRoot/build/fixtures" "$phaseRoot/rtl/phase4_polar_top.sv" "$phaseRoot/sim/tb_phase4_polar.sv"
    if($LASTEXITCODE -ne 0){throw 'SV compile failed'}
    & "$VivadoRoot/bin/xvhdl.bat" --work xil_defaultlib "$phaseRoot/build/vivado/phase4_polar.gen/sources_1/ip/polar32/sim/polar32.vhd"
    if($LASTEXITCODE -ne 0){throw 'IP wrapper compile failed'}
    & "$VivadoRoot/bin/xelab.bat" --debug typical --relax -L xil_defaultlib -L cordic_v6_0_16 -L secureip --snapshot phase4_sim xil_defaultlib.tb_phase4_polar
    if($LASTEXITCODE -ne 0){throw 'Elaboration failed'}
    & "$VivadoRoot/bin/xsim.bat" phase4_sim --runall --log polar_sim.log
    if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
    $simText=Get-Content -LiteralPath polar_sim.log -Raw
    if($simText -notmatch 'PHASE4_POLAR_PASS' -or $simText -match 'Fatal:|Error:'){throw 'CORDIC assertions failed'}
    Copy-Item -LiteralPath polar_sim.log,polar_results.csv -Destination "$phaseRoot/build/reports" -Force
} finally {Pop-Location}
