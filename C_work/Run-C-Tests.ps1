param(
    [switch]$Full,
    [string]$Layers = '',
    [string]$Python = 'python',
    [string]$WslDistro = 'Ubuntu-24.04'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & $Python scripts/run_unit.py
    if ($LASTEXITCODE -ne 0) { throw 'C interface tests failed.' }
    $socArguments = @('scripts/run_soc.py', '--wsl-distro', $WslDistro)
    if ($Full) {
        $socArguments += '--full'
        if (!$Layers) { $Layers = '0,1,2,3,4,5,6,7,8,9,10,11' }
    }
    if ($Layers) { $socArguments += @('--layers', $Layers) }
    & $Python @socArguments
    if ($LASTEXITCODE -ne 0) { throw 'E203 SoC tests failed.' }
} finally { Pop-Location }
