# =============================================================================
# Step 1: Migrate IT Glue Organizations -> ITFlow Clients
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Client Migration ==="

$orgs = Get-ITGlueAll -Endpoint "organizations"
Write-Log "Found $($orgs.Count) organizations in IT Glue"

$clientMap = @{}  # IT Glue org ID -> ITFlow client ID

foreach ($org in $orgs) {
    $attr = $org.attributes

    $body = @{
        client_name         = $attr.name
        client_type         = $attr.'organization-type-name' ?? ''
        client_website      = $attr.'primary-website' ?? ''
        client_notes        = $attr.'quick-notes' ?? ''
        client_abbreviation = ($attr.'short-name' ?? '').Substring(0, [Math]::Min(6, ($attr.'short-name' ?? '').Length))
    }

    Write-Log "Migrating client: $($attr.name) (ITGlue ID: $($org.id))"
    $result = Send-ITFlowCreate -Endpoint "clients" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $clientMap[$org.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow client ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create client: $($attr.name)" "ERROR"
    }
}

Save-Mapping -Type "clients" -Map $clientMap
Write-Log "=== Client Migration Complete: $($clientMap.Count) migrated ==="
