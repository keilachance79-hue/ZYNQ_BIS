param(
    [string]$Vivado = 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$phaseRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $phaseRoot '..')).Path
$phaseRunRoot = $phaseRoot
$phaseDrive = $null
# Map the repository so the frozen Phase1 input remains reachable as a sibling.
if ($repoRoot -match '[^\x00-\x7F]') {
    foreach ($letter in @('Z','Y','X','W','V','U','T','S','R','Q','P')) {
        if (-not (Test-Path -LiteralPath "${letter}:\")) {
            & subst.exe "${letter}:" $repoRoot
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create ASCII drive alias' }
            $phaseDrive = "${letter}:"
            $phaseRunRoot = "${letter}:\Phase2"
            break
        }
    }
    if (-not $phaseDrive) { throw 'Use an ASCII checkout path; no unused drive letter' }
}
Push-Location -LiteralPath $phaseRunRoot
try {
    & $Python scripts/generate_fixtures.py
    if ($LASTEXITCODE -ne 0) { throw 'Fixture generation failed' }
    & $Vivado -mode batch -source scripts/run_sim.tcl -log build_sim.log -journal build_sim.jou
    if ($LASTEXITCODE -ne 0) { throw 'Capture simulation failed' }
    & $Python scripts/check_capture.py
    if ($LASTEXITCODE -ne 0) { throw 'Raw reference/FFT check failed' }
    & $Vivado -mode batch -source scripts/run_synth.tcl -log build_synth.log -journal build_synth.jou
    if ($LASTEXITCODE -ne 0) { throw 'Capture synthesis failed' }
    & $Vivado -mode batch -source scripts/check_device_pins.tcl -log pin_audit.log -journal pin_audit.jou
    if ($LASTEXITCODE -ne 0) { throw 'Package pin audit failed' }
    & $Python scripts/export_verification.py
    if ($LASTEXITCODE -ne 0) { throw 'Evidence export failed' }
    Write-Output 'PHASE2_PROTOTYPE_CHECKS_PASS (board and PS/DMA acceptance pending)'
}
finally {
    Pop-Location
    if ($phaseDrive) { & subst.exe $phaseDrive /D }
}
