# Run dbt with env loaded and --target from DBT_TARGET (.env).
# Usage:  .\scripts\dbt.ps1 run
#         .\scripts\dbt.ps1 test --select staging

. "$PSScriptRoot\load_env.ps1"

$target = $env:DBT_TARGET
if (-not $target) { $target = "dev" }

$dbtArgs = @("--target", $target) + $args
Write-Host "dbt $($args -join ' ') --target $target"
& dbt @dbtArgs
