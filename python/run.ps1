$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$gamePython = $null
$gameCandidates = @(
    (Join-Path $PSScriptRoot '.venv\Scripts\python.exe'),
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
)
foreach ($candidate in $gameCandidates) {
    if (Test-Path -LiteralPath $candidate) {
        $gamePython = $candidate
        break
    }
}
if (-not $gamePython) {
    foreach ($commandName in @('python', 'py')) {
        $pythonCommand = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($pythonCommand) {
            $gamePython = $pythonCommand.Source
            break
        }
    }
}
if (-not $gamePython) {
    Write-Host 'Python 3.10+ is required. Install it from https://www.python.org/downloads/ and enable Add Python to PATH.'
    exit 1
}

$env:PYGAME_HIDE_SUPPORT_PROMPT = '1'
$gameDependencyProbe = @'
import sys
sys.path.insert(0, '.deps')
try:
    import pygame
    available = hasattr(pygame, 'KSCAN_A')
except Exception:
    available = False
sys.exit(0 if available else 1)
'@
& $gamePython -c $gameDependencyProbe
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Installing pygame-ce into the local .deps folder...'
    & $gamePython -m pip install --target .deps --upgrade -r requirements.txt --disable-pip-version-check
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $gamePython (Join-Path $PSScriptRoot 'tetris.py') @args
exit $LASTEXITCODE
