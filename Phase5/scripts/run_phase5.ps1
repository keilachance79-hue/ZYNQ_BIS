param(
    [string]$Vivado='D:/Application/Xilinx/Vivado/2020.2/bin/vivado.bat',
    [string]$Python='python'
)
$ErrorActionPreference='Stop'
$phaseRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $phaseRoot '..')).Path
$vivadoRoot=Split-Path -Parent (Split-Path -Parent $Vivado)
$phaseRunRoot=$phaseRoot
$phaseDrive=$null
if($repoRoot -match '[^\x00-\x7F]') {
    foreach($letter in @('Z','Y','X','W','V','U','T','S','R','Q','P')) {
        if(-not (Test-Path -LiteralPath "${letter}:\")) {
            & subst.exe "${letter}:" $repoRoot
            if($LASTEXITCODE -ne 0){throw 'Unable to create ASCII drive alias'}
            $phaseDrive="${letter}:";$phaseRunRoot="${letter}:\Phase5";break
        }
    }
    if(-not $phaseDrive){throw 'Use an ASCII checkout; no unused drive letter'}
}
Push-Location -LiteralPath $phaseRunRoot
try {
    & $Python scripts/generate.py
    if($LASTEXITCODE -ne 0){throw 'Mapping/scan generation failed'}
    & ./scripts/run_xsim.ps1 -VivadoRoot $vivadoRoot
    & $Vivado -mode batch -source scripts/run_synth.tcl -log synth.log -journal synth.jou
    if($LASTEXITCODE -ne 0){throw 'Synthesis failed'}
    & $Python scripts/export_verification.py
    if($LASTEXITCODE -ne 0){throw 'Evidence export failed'}
    Write-Output 'PHASE5_DIGITAL_CHECKS_PASS (board and analog acceptance pending)'
} finally {
    Pop-Location
    if($phaseDrive){& subst.exe $phaseDrive /D}
}
