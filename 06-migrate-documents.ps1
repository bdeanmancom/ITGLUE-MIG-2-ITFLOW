# =============================================================================
# Step 6: Migrate IT Glue Documents -> ITFlow Documents
# =============================================================================

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\helpers.ps1"
Initialize-Migration

Write-Log "=== Starting Document Migration ==="

$clientMap = Load-Mapping -Type "clients"
if ($clientMap.Count -eq 0) { Write-Log "No client mapping found. Run 01 first." "ERROR"; exit 1 }

# IT Glue documents are in "flexible_assets" — fetch all flexible asset types first
$faTypes = Get-ITGlueAll -Endpoint "flexible_asset_types"
Write-Log "Found $($faTypes.Count) flexible asset types"

$docMap = @{}

foreach ($faType in $faTypes) {
    $typeName = $faType.attributes.name
    Write-Log "Processing flexible asset type: $typeName"

    $flexAssets = Get-ITGlueAll -Endpoint "flexible_assets" -QueryParams @{
        "filter[flexible_asset_type_id]" = $faType.id
    }

    foreach ($fa in $flexAssets) {
        $attr = $fa.attributes
        $itglueOrgId = ($fa.attributes.'organization-id' ?? $fa.relationships.'organization'.data.id).ToString()
        $itflowClientId = $clientMap[$itglueOrgId]

        if (-not $itflowClientId) {
            Write-Log "  Skipping flex asset '$($attr.name)' - no matching client" "WARN"
            continue
        }

        # Build document content from traits
        $contentParts = @("<h2>$typeName - $($attr.name)</h2>")
        foreach ($trait in $attr.traits) {
            $label = $trait.'trait-type' ?? $trait.name ?? 'Field'
            $value = $trait.value ?? ''
            if ($value -is [array]) { $value = $value -join ', ' }
            if (-not [string]::IsNullOrEmpty($value)) {
                $contentParts += "<p><strong>${label}:</strong> $value</p>"
            }
        }
        $htmlContent = $contentParts -join "`n"

        $body = @{
            document_name        = "$typeName - $($attr.name)"
            document_description = "Migrated from IT Glue flexible asset type: $typeName"
            document_content     = $htmlContent
            client_id            = $itflowClientId
        }

        Write-Log "Migrating document: $typeName - $($attr.name) -> client $itflowClientId"
        $result = Send-ITFlowCreate -Endpoint "documents" -Body $body

        if ($result -and $result.success) {
            $newId = $result.data[0].insert_id ?? $result.data.insert_id ?? 0
            $docMap[$fa.id.ToString()] = $newId
            Write-Log "  -> Created ITFlow document ID: $newId"
        }
        else {
            Write-Log "  -> FAILED to create document: $($attr.name)" "ERROR"
        }
    }
}

Save-Mapping -Type "documents" -Map $docMap
Write-Log "=== Document Migration Complete: $($docMap.Count) migrated ==="
