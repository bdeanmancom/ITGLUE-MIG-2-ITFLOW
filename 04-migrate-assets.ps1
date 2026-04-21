# =============================================================================
# Step 4: Migrate IT Glue Configurations -> ITFlow Assets
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Asset Migration ==="

$clientMap   = Load-Mapping -Type "clients"
$locationMap = Load-Mapping -Type "locations"
$contactMap  = Load-Mapping -Type "contacts"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01 first." "ERROR"; exit 1 }

$configs = Get-ITGlueAll -Endpoint "configurations"
Write-Log "Found $($configs.Count) configurations in IT Glue"

$assetMap = @{}

# Map IT Glue configuration-type to ITFlow asset types
$typeMap = @{
    "Firewall"       = "Firewall"
    "Switch"         = "Switch"
    "Router"         = "Router"
    "Server"         = "Server"
    "Workstation"    = "Desktop"
    "Laptop"         = "Laptop"
    "Printer"        = "Printer"
    "Access Point"   = "Access Point"
    "Virtual Machine"= "Virtual Machine"
    "Phone"          = "Phone"
    "Camera"         = "Camera"
    "UPS"            = "UPS"
}

foreach ($cfg in $configs) {
    $attr = $cfg.attributes
    $itglueOrgId = ($cfg.attributes.'organization-id' ?? $cfg.relationships.'organization'.data.id).ToString()
    $itflowClientId = $clientMap[$itglueOrgId]

    if (-not $itflowClientId) {
        Write-Log "  Skipping config '$($attr.name)' - no matching client" "WARN"
        continue
    }

    $itglueType = $attr.'configuration-type-name' ?? ''
    $itflowType = $typeMap[$itglueType] ?? $itglueType

    # Map location
    $itflowLocationId = 0
    $locData = $cfg.relationships.location.data ?? $null
    if ($locData) { $itflowLocationId = $locationMap[$locData.id.ToString()] ?? 0 }

    # Map contact
    $itflowContactId = 0
    $contactData = $cfg.relationships.'primary-contact'.data ?? $null
    if ($contactData) { $itflowContactId = $contactMap[$contactData.id.ToString()] ?? 0 }

    # Parse IP from primary_ip or notes
    $ip = $attr.'primary-ip' ?? ''

    # Parse MAC
    $mac = $attr.'mac-address' ?? ''

    # Warranty
    $warrantyExpire = $attr.'warranty-expires-at' ?? ''

    $body = @{
        asset_name          = $attr.name ?? 'Unknown'
        asset_description   = $attr.'configuration-type-name' ?? ''
        asset_type          = $itflowType
        asset_make          = $attr.'manufacturer-name' ?? ''
        asset_model         = $attr.'model-name' ?? ''
        asset_serial        = $attr.'serial-number' ?? ''
        asset_os            = $attr.'operating-system-notes' ?? ''
        asset_ip            = $ip
        asset_mac           = $mac
        asset_status        = if ($attr.archived -eq $true) { "Retired" } else { "Active" }
        asset_warranty_expire = $warrantyExpire
        asset_notes         = $attr.notes ?? ''
        asset_location_id   = $itflowLocationId
        asset_contact_id    = $itflowContactId
        client_id           = $itflowClientId
    }

    Write-Log "Migrating asset: $($attr.name) ($itflowType) -> client $itflowClientId"
    $result = Send-ITFlowCreate -Endpoint "assets" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $assetMap[$cfg.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow asset ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create asset: $($attr.name)" "ERROR"
    }
}

Save-Mapping -Type "assets" -Map $assetMap
Write-Log "=== Asset Migration Complete: $($assetMap.Count) migrated ==="
