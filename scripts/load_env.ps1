# Load .env into the current PowerShell session for dbt / BigQuery.
# Usage:  . .\scripts\load_env.ps1

$envFile = Join-Path $PSScriptRoot "..\.env" | Resolve-Path -ErrorAction SilentlyContinue

if (-not $envFile) {
    Write-Error ".env not found. Copy .env.example to .env and fill in values."
    return
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
}

Write-Host "Loaded env from $($envFile.Path)"
Write-Host "  BQ_PROJECT_ID=$env:BQ_PROJECT_ID"
Write-Host "  BQ_DATASET_RAW=$env:BQ_DATASET_RAW"
Write-Host "  BQ_DATASET_STG=$env:BQ_DATASET_STG"
Write-Host "  BQ_DATASET_INT=$env:BQ_DATASET_INT"
Write-Host "  BQ_DATASET_MART=$env:BQ_DATASET_MART"
Write-Host "  DBT_TARGET=$env:DBT_TARGET  (use: dbt run --target `$env:DBT_TARGET  or  .\scripts\dbt.ps1 run)"
Write-Host "  DBT_PROFILES_DIR=$env:DBT_PROFILES_DIR"
