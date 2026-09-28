param(
    [string]$Vivado = 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$phaseRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$phaseRunRoot = $phaseRoot
$phaseDrive = $null
# Vivado 2020.2 synthesis crashed internally in the original Unicode path.
# A temporary drive alias changes no files and avoids that toolchain issue.
if ($phaseRoot -match '[^\x00-\x7F]') {
    foreach ($letter in @('Z','Y','X','W','V','U','T','S','R','Q','P')) {
        if (-not (Test-Path -LiteralPath "${letter}:\")) {
            & subst.exe "${letter}:" $phaseRoot
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create temporary ASCII drive alias' }
            $phaseDrive = "${letter}:"
            $phaseRunRoot = "${letter}:\"
            break
        }
    }
    if (-not $phaseDrive) { throw 'No unused drive letter is available; use an ASCII checkout path' }
}
Push-Location -LiteralPath $phaseRunRoot
try {
    & $Python scripts/generate_multisine.py
    if ($LASTEXITCODE -ne 0) { throw 'Waveform generation failed' }
    & $Python scripts/check_waveform.py --reproduce
    if ($LASTEXITCODE -ne 0) { throw 'Reference validation failed' }
    & $Vivado -mode batch -source scripts/run_sim.tcl -log build_sim.log -journal build_sim.jou
    if ($LASTEXITCODE -ne 0) { throw 'Vivado simulation failed' }
    & $Python scripts/check_waveform.py --capture build/reports/dac_capture.csv --report verification/waveform_check.json --reproduce
    if ($LASTEXITCODE -ne 0) { throw 'Captured DAC comparison failed' }
    & $Vivado -mode batch -source scripts/run_synth.tcl -log build_synth.log -journal build_synth.jou
    if ($LASTEXITCODE -ne 0) { throw 'Vivado synthesis failed' }
    & $Python scripts/export_verification.py
    if ($LASTEXITCODE -ne 0) { throw 'Verification export failed' }
    Write-Output 'PHASE1_DIGITAL_CHECKS_PASS (board implementation and bench test remain pending)'
}
finally {
    Pop-Location
    if ($phaseDrive) { & subst.exe $phaseDrive /D }
}
