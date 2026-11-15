param(
    [ValidateSet('run', 'editor', 'check', 'test', 'capture')]
    [string]$Action = 'run'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$engineExe = $env:GODOT_EXE
if (-not $engineExe) { $engineExe = [Environment]::GetEnvironmentVariable('GODOT_EXE', 'User') }
if (-not $engineExe -or -not (Test-Path -LiteralPath $engineExe)) {
    throw 'Set GODOT_EXE to the Godot console executable before using this script.'
}
$engineArgs = @('--path', $projectDir)
switch ($Action) {
    'editor' { $engineArgs += '--editor' }
    'check' { $engineArgs += @('--headless', '--editor', '--import') }
    'test' { $engineArgs += @('--headless', '--script', 'res://tests/run_tests.gd') }
    'capture' { $engineArgs += @('--', '--capture') }
}
function Invoke-Engine {
    param([string[]]$EngineArguments)
    # Collect native stderr without PowerShell treating each line as an exception.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $engineExe @EngineArguments 2>&1 | Tee-Object -Variable engineOutput
    $engineExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    $reportedErrors = @($engineOutput | Where-Object { $_.ToString() -match '^(SCRIPT ERROR:|ERROR:)' })
    if ($engineExitCode -ne 0 -or $reportedErrors.Count -gt 0) {
        throw 'Godot reported a failure. See the output above.'
    }
}
Invoke-Engine $engineArgs
if ($Action -eq 'check') {
    Invoke-Engine @('--headless', '--path', $projectDir, '--script', 'res://tools/validate_scripts.gd')
}
if ($Action -eq 'test') {
    foreach ($probe in @('path_economy_tests', 'pathfinding_tests', 'targeting_probe', 'selection_probe', 'integration_tests', 'worker_tests', 'mining_sides_tests', 'room_tests', 'treasury_worker_tests', 'room_input_tests', 'room_review_tests', 'bed_tests', 'resident_tests', 'resident_ui_tests', 'resident_review_tests', 'full_treasury_tests', 'bedrock_tests', 'food_tests', 'feeding_tests', 'food_ui_tests', 'food_review_tests', 'pig_life_tests', 'starting_gold_tests', 'keeper_tests', 'keeper_behavior_tests', 'keeper_ui_tests', 'keeper_input_tests', 'keeper_drop_review_tests', 'keeper_gold_tests', 'keeper_gold_review_tests', 'keeper_queue_tests', 'keeper_queue_review_tests', 'save_state_tests', 'save_review_tests', 'save_ui_tests', 'feature_save_tests', 'save_integration_tests', 'infrastructure_worker_tests', 'exploration_review_tests', 'fog_planning_tests', 'wall_lamp_tests', 'room_corner_tests')) {
        Invoke-Engine @('--headless', '--path', $projectDir, '--script', "res://tests/$probe.gd")
    }
}
exit 0
