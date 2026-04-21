# =============================================================================
# Step 7: Migrate IT Glue Domains -> ITFlow Domains
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Domain Migration ==="

$clientMap = Load-Mapping -Type "clients"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01 first." "ERROR"; exit 1 }

$domains = Get-ITGlueAll -Endpoint "domains"
Write-Log "Found $($domains.Count) domains in IT Glue"

$domainMap = @{}

foreach ($d in $domains) {
    $attr = $d.attributes
    $itglueOrgId = ($d.attributes.'organization-id' ?? $d.relationships.'organization'.data.id).ToString()
    $itflowClientId = $clientMap[$itglueOrgId]

    if (-not $itflowClientId) {
        Write-Log "  Skipping domain '$($attr.name)' - no matching client" "WARN"
        continue
    }

    $body = @{
        domain_name        = $attr.name ?? ''
        domain_description = $attr.notes ?? ''
        domain_registrar   = $attr.'registrar-name' ?? ''
        domain_expire      = ($attr.'expires-on' ?? '').Split('T')[0]  # yyyy-mm-dd
        domain_notes       = $attr.notes ?? ''
        client_id          = $itflowClientId
    }

    Write-Log "Migrating domain: $($attr.name) -> client $itflowClientId"
    $result = Send-ITFlowCreate -Endpoint "domains" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $domainMap[$d.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow domain ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create domain: $($attr.name)" "ERROR"
    }
}

Save-Mapping -Type "domains" -Map $domainMap
Write-Log "=== Domain Migration Complete: $($domainMap.Count) migrated ==="
