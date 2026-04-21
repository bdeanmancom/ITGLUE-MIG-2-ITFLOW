# =============================================================================
# IT Glue -> ITFlow Migration - Configuration
# =============================================================================

# IT Glue API
$ITGlue_APIKey   = "<ITG.YOUR KEY HERE>"
$ITGlue_BaseURL  = "https://api.itglue.com"

# ITFlow API
$ITFlow_APIKey   = "<YOUR API KEY HERE>"
$ITFlow_BaseURL  = "https://itflow.somedomain.com"

# Credential encryption password (must match the API key's decrypt password in ITFlow)
$ITFlow_CredentialDecryptPassword = "YOUR_API_KEY_DECRYPT_PASSWORD"

# Migration options
$DryRun          = $false   # Set to $true to preview without writing
$LogFile         = "$PSScriptRoot\migration.log"

# ID mapping files (auto-generated during migration)
$MappingDir      = "$PSScriptRoot\mappings"
