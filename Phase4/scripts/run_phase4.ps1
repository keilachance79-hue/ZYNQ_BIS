param(
    [string]$Vivado = 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$phaseRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $phaseRoot '..')).Path
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$phaseRunRoot = $phaseRoot
$phaseDrive = $null
if ($repoRoot -match '[^\x00-\x7F]') {
    foreach ($letter in @('Z','Y','X','W','V','U','T','S','R','Q','P')) {
        if (-not (Test-Path -LiteralPath "${letter}:\")) {
            & subst.exe "${letter}:" $repoRoot
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create ASCII drive alias' }
            $phaseDrive = "${letter}:"
            $phaseRunRoot = "${letter}:\Phase4"
            break
        }
    }
    if (-not $phaseDrive) { throw 'Use an ASCII checkout path; no unused drive letter' }
}
Push-Location -LiteralPath $phaseRunRoot
try {
    & $Python scripts/generate_fixtures.py --vivado-root $vivadoRoot
    if ($LASTEXITCODE -ne 0) { throw 'CORDIC reference generation failed' }
    & $Vivado -mode batch -source scripts/create_project.tcl -log ip.log -journal ip.jou
    if ($LASTEXITCODE -ne 0) { throw 'CORDIC IP generation failed' }
    & ./scripts/run_xsim.ps1 -VivadoRoot $vivadoRoot
    & $Vivado -mode batch -source scripts/run_synth.tcl -log synth.log -journal synth.jou
    if ($LASTEXITCODE -ne 0) { throw 'CORDIC synthesis failed' }
    & $Python scripts/export_verification.py
    if ($LASTEXITCODE -ne 0) { throw 'Evidence export failed' }
    Write-Output 'PHASE4_DIGITAL_CHECKS_PASS (physical ADC and board acceptance pending)'
}
finally {
    Pop-Location
    if ($phaseDrive) { & subst.exe $phaseDrive /D }
}

