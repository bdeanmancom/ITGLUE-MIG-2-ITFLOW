# =============================================================================
# Step 2: Migrate IT Glue Locations -> ITFlow Locations
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Location Migration ==="

$clientMap = Load-Mapping -Type "clients"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01-migrate-clients.ps1 first." "ERROR"; exit 1 }

$locations = Get-ITGlueAll -Endpoint "locations"
Write-Log "Found $($locations.Count) locations in IT Glue"

$locationMap = @{}

foreach ($loc in $locations) {
    $attr = $loc.attributes
    $itglueOrgId = ($loc.attributes.'organization-id' ?? $loc.relationships.'organization'.data.id).ToString()
    $itflowClientId = $clientMap[$itglueOrgId]

    if (-not $itflowClientId) {
        Write-Log "  Skipping location '$($attr.name)' - no matching client for org $itglueOrgId" "WARN"
        continue
    }

    $body = @{
        location_name        = $attr.name
        location_address     = "$($attr.'address-1') $($attr.'address-2')".Trim()
        location_city        = $attr.city ?? ''
        location_state       = $attr.'region-name' ?? ''
        location_zip         = $attr.'postal-code' ?? ''
        location_country     = $attr.'country-name' ?? ''
        location_notes       = $attr.notes ?? ''
        location_primary     = if ($attr.primary) { 1 } else { 0 }
        client_id            = $itflowClientId
    }

    Write-Log "Migrating location: $($attr.name) -> client $itflowClientId"
    $result = Send-ITFlowCreate -Endpoint "locations" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $locationMap[$loc.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow location ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create location: $($attr.name)" "ERROR"
    }
}

Save-Mapping -Type "locations" -Map $locationMap
Write-Log "=== Location Migration Complete: $($locationMap.Count) migrated ==="
