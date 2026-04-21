# =============================================================================
# Step 3: Migrate IT Glue Contacts -> ITFlow Contacts
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Contact Migration ==="

$clientMap   = Load-Mapping -Type "clients"
$locationMap = Load-Mapping -Type "locations"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01 first." "ERROR"; exit 1 }

$contacts = Get-ITGlueAll -Endpoint "contacts"
Write-Log "Found $($contacts.Count) contacts in IT Glue"

$contactMap = @{}

foreach ($c in $contacts) {
    $attr = $c.attributes
    $itglueOrgId = ($c.attributes.'organization-id' ?? $c.relationships.'organization'.data.id).ToString()
    $itflowClientId = $clientMap[$itglueOrgId]

    if (-not $itflowClientId) {
        Write-Log "  Skipping contact '$($attr.'first-name') $($attr.'last-name')' - no matching client" "WARN"
        continue
    }

    # Map location if available
    $itflowLocationId = 0
    $locData = $c.relationships.'contact-location'.data ?? $c.relationships.location.data ?? $null
    if ($locData) { $itflowLocationId = $locationMap[$locData.id.ToString()] ?? 0 }

    # Build primary email (IT Glue stores emails in contact-emails)
    $primaryEmail = ""
    foreach ($e in $attr.'contact-emails') {
        if ($e.'label-name' -eq 'Work' -or $e.primary -eq $true -or [string]::IsNullOrEmpty($primaryEmail)) {
            $primaryEmail = $e.value
        }
    }

    # Build primary phone
    $primaryPhone = ""
    $mobile = ""
    foreach ($p in $attr.'contact-phones') {
        if ($p.'label-name' -eq 'Work' -or $p.primary -eq $true) {
            $primaryPhone = $p.value
            if ($p.extension) { $extension = $p.extension }
        }
        if ($p.'label-name' -eq 'Mobile') {
            $mobile = $p.value
        }
    }

    $fullName = "$($attr.'first-name') $($attr.'last-name')".Trim()

    $body = @{
        contact_name        = $fullName
        contact_title       = $attr.title ?? ''
        contact_email       = $primaryEmail
        contact_phone       = $primaryPhone -replace '[^0-9]', ''
        contact_extension   = $extension ?? ''
        contact_mobile      = $mobile -replace '[^0-9]', ''
        contact_notes       = $attr.notes ?? ''
        contact_important   = if ($attr.important) { 1 } else { 0 }
        contact_location_id = $itflowLocationId
        client_id           = $itflowClientId
    }

    if ([string]::IsNullOrEmpty($primaryEmail)) {
        Write-Log "  Skipping contact '$fullName' - no email address" "WARN"
        continue
    }

    Write-Log "Migrating contact: $fullName ($primaryEmail) -> client $itflowClientId"
    $result = Send-ITFlowCreate -Endpoint "contacts" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $contactMap[$c.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow contact ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create contact: $fullName" "ERROR"
    }
}

Save-Mapping -Type "contacts" -Map $contactMap
Write-Log "=== Contact Migration Complete: $($contactMap.Count) migrated ==="
