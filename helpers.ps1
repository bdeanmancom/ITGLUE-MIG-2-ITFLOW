# =============================================================================
# Shared helper functions
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Initialize-Migration {
    if (-not (Test-Path $MappingDir)) { New-Item -ItemType Directory -Path $MappingDir -Force | Out-Null }
    if (-not (Test-Path $LogFile))    { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
}

# --- IT Glue API helpers ---

function Get-ITGlueAll {
    param([string]$Endpoint, [hashtable]$QueryParams = @{})

    $headers = @{
        "x-api-key"    = $ITGlue_APIKey
        "Content-Type" = "application/vnd.api+json"
    }

    $allData  = @()
    $page     = 1
    $pageSize = 250

    do {
        $QueryParams["page[size]"]   = $pageSize
        $QueryParams["page[number]"] = $page

        $qs = ($QueryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join "&"
        $url = "$ITGlue_BaseURL/$Endpoint`?$qs"

        try {
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
            $allData += $resp.data
            $totalPages = [int]($resp.meta.'total-pages' ?? $resp.meta.total_pages ?? 1)
            Write-Log "  Fetched page $page/$totalPages of $Endpoint ($($resp.data.Count) records)"
            $page++
        }
        catch {
            Write-Log "Error fetching $Endpoint page $page`: $_" "ERROR"
            break
        }
    } while ($page -le $totalPages)

    return $allData
}

function Get-ITGluePassword {
    param([string]$PasswordId, [string]$OrgId)

    $headers = @{
        "x-api-key"    = $ITGlue_APIKey
        "Content-Type" = "application/vnd.api+json"
    }

    $url = "$ITGlue_BaseURL/organizations/$OrgId/relationships/passwords/$PasswordId`?show_password=true"

    try {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        return $resp.data
    }
    catch {
        Write-Log "Error fetching password $PasswordId`: $_" "ERROR"
        return $null
    }
}

# --- ITFlow API helpers ---

function Send-ITFlowCreate {
    param([string]$Endpoint, [hashtable]$Body)

    $Body["api_key"] = $ITFlow_APIKey
    $uri = "$ITFlow_BaseURL/api/v1/$Endpoint/create.php"

    if ($DryRun) {
        Write-Log "[DRY RUN] Would POST to $uri with: $($Body | ConvertTo-Json -Compress)" "DRY"
        return @{ success = $true; data = @{ id = 0 } }
    }

    try {
        $jsonBody = $Body | ConvertTo-Json -Depth 5
        $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
        return $resp
    }
    catch {
        Write-Log "Error posting to $uri`: $_" "ERROR"
        return $null
    }
}

# --- Mapping persistence ---

function Save-Mapping {
    param([string]$Type, [hashtable]$Map)
    $path = Join-Path $MappingDir "$Type.json"
    $Map | ConvertTo-Json -Depth 5 | Set-Content -Path $path
}

function Load-Mapping {
    param([string]$Type)
    $path = Join-Path $MappingDir "$Type.json"
    if (Test-Path $path) {
        return (Get-Content -Path $path -Raw | ConvertFrom-Json -AsHashtable)
    }
    return @{}
}
