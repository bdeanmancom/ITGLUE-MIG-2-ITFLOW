# =============================================================================
# IT Glue -> ITFlow Full Migration Runner
# Run scripts in order — each depends on the previous mapping files
# =============================================================================

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

Write-Host "============================================"
Write-Host "  IT Glue -> ITFlow Migration"
Write-Host "============================================"
Write-Host ""

$steps = @(
    @{ Script = "01-migrate-clients.ps1";     Desc = "Organizations -> Clients" }
    @{ Script = "02-migrate-locations.ps1";   Desc = "Locations -> Locations" }
    @{ Script = "03-migrate-contacts.ps1";    Desc = "Contacts -> Contacts" }
    @{ Script = "04-migrate-assets.ps1";      Desc = "Configurations -> Assets" }
    @{ Script = "05-migrate-credentials.ps1"; Desc = "Passwords -> Credentials" }
    @{ Script = "06-migrate-documents.ps1";   Desc = "Flexible Assets -> Documents" }
    @{ Script = "07-migrate-domains.ps1";     Desc = "Domains -> Domains" }
)

foreach ($step in $steps) {
    Write-Host ""
    Write-Host "--- $($step.Desc) ---"
    $confirm = Read-Host "Run $($step.Script)? (Y/n/skip)"
    if ($confirm -eq 'n') {
        Write-Host "Aborting migration."
        exit 0
    }
    if ($confirm -eq 'skip') {
        Write-Host "Skipping $($step.Script)"
        continue
    }

    & "$scriptDir\$($step.Script)"

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "Script $($step.Script) failed. Aborting." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host "  Migration Complete!"
Write-Host "  Check migration.log for details"
Write-Host "  ID mappings saved in ./mappings/"
Write-Host "============================================"
