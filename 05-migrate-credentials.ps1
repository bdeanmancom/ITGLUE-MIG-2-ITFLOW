# =============================================================================
# Step 5: Migrate IT Glue Passwords -> ITFlow Credentials
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Credential Migration ==="

$clientMap  = Load-Mapping -Type "clients"
$assetMap   = Load-Mapping -Type "assets"
$contactMap = Load-Mapping -Type "contacts"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01 first." "ERROR"; exit 1 }

# Fetch password list (bulk - passwords will be empty)
$passwords = Get-ITGlueAll -Endpoint "passwords"
Write-Log "Found $($passwords.Count) passwords in IT Glue"

$credMap = @{}
$count = 0

foreach ($pw in $passwords) {
    $count++
    $attr = $pw.attributes
    $itglueOrgId = ($pw.attributes.'organization-id' ?? $pw.relationships.'organization'.data.id).ToString()
    $itflowClientId = $clientMap[$itglueOrgId]

    if (-not $itflowClientId) {
        Write-Log "  Skipping password '$($attr.name)' - no matching client" "WARN"
        continue
    }

    # Fetch individual password with show_password=true
    Write-Log "  Fetching password details ($count/$($passwords.Count)): $($attr.name)"
    $fullPw = Get-ITGluePassword -PasswordId $pw.id.ToString() -OrgId $itglueOrgId
    if (-not $fullPw) {
        Write-Log "  -> FAILED to fetch password details for '$($attr.name)'" "ERROR"
        continue
    }
    $fullAttr = $fullPw.attributes

    $password = $fullAttr.password ?? ''
    if ([string]::IsNullOrEmpty($password)) {
        Write-Log "  Skipping password '$($attr.name)' - empty password" "WARN"
        continue
    }

    # Map linked resource (configuration -> asset)
    $itflowAssetId = 0
    $resData = $pw.relationships.resource.data ?? $null
    if ($resData -and $resData.type -eq "configurations") {
        $itflowAssetId = $assetMap[$resData.id.ToString()] ?? 0
    }

    $body = @{
        credential_name        = $fullAttr.name ?? 'Unnamed'
        credential_description = $fullAttr.notes ?? ''
        credential_uri         = $fullAttr.url ?? ''
        credential_username    = $fullAttr.username ?? ''
        credential_password    = $password
        credential_otp_secret  = $fullAttr.'otp-secret' ?? ''
        credential_note        = $fullAttr.'password-category-name' ?? ''
        credential_asset_id    = $itflowAssetId
        client_id              = $itflowClientId
        api_key_decrypt_password = $ITFlow_CredentialDecryptPassword
    }

    Write-Log "Migrating credential: $($fullAttr.name) -> client $itflowClientId"
    $result = Send-ITFlowCreate -Endpoint "credentials" -Body $body

    if ($result -and $result.success) {
        $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
        $credMap[$pw.id.ToString()] = $newId
        Write-Log "  -> Created ITFlow credential ID: $newId"
    }
    else {
        Write-Log "  -> FAILED to create credential: $($fullAttr.name)" "ERROR"
    }
}

Save-Mapping -Type "credentials" -Map $credMap
Write-Log "=== Credential Migration Complete: $($credMap.Count) migrated ==="
