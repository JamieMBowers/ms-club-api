# Updates only this machine's Azure SQL firewall rule and wakes the database.
# Run it whenever your network's public IP changes (for example, before a presentation).
# Requires Windows PowerShell, the Azure CLI, `az login`, and an existing SQL database.
param(
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ServerName,
    [string]$RuleName,
    [string]$DatabaseName,
    [switch]$Configure,
    [switch]$NonInteractive,
    [switch]$SkipDatabaseWarmup
)

$ErrorActionPreference = "Stop"

function Read-RequiredSetting([string]$Label, [string]$DefaultValue) {
    do {
        $prompt = if ($DefaultValue) { "$Label [$DefaultValue]" } else { $Label }
        $value = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $DefaultValue }
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
        Write-Warning "$Label is required."
    } while ($true)
}

if ($Configure -and $NonInteractive) {
    throw "-Configure cannot be combined with -NonInteractive."
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required. Install it, run 'az login', then try again."
}

$configPath = Join-Path $PSScriptRoot "sql-firewall.local.json"
$settings = [ordered]@{
    SubscriptionId = $SubscriptionId
    ResourceGroup = $ResourceGroup
    ServerName = $ServerName
    DatabaseName = $DatabaseName
    RuleName = $RuleName
}
if (-not $Configure -and (Test-Path -LiteralPath $configPath)) {
    Write-Host "Loading local settings from '$configPath'. Use -Configure to replace them."
    $savedSettings = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    foreach ($key in @($settings.Keys)) {
        if ([string]::IsNullOrWhiteSpace($settings[$key])) {
            $property = $savedSettings.PSObject.Properties[$key]
            if ($null -ne $property) {
                if ($property.Value -isnot [string]) {
                    throw "Invalid saved setting '$key'. Run this script with -Configure to replace local settings."
                }
                $settings[$key] = $property.Value.Trim()
            }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($settings.RuleName)) {
    $settings.RuleName = "dev-$([Environment]::MachineName)"
}
$missingSettings = @($settings.Keys | Where-Object { [string]::IsNullOrWhiteSpace($settings[$_]) })
$needsSetup = $Configure -or $missingSettings.Count -gt 0
if ($needsSetup) {
    if ($NonInteractive) {
        throw "Azure settings are incomplete. Run .\scripts\Update-SqlFirewall.ps1 -Configure in a terminal first."
    }
    $subscriptionsJson = az account list --query "[?state=='Enabled'].{name:name,id:id}" -o json
    if ($LASTEXITCODE -ne 0) { throw "Could not list subscriptions. Run 'az login' and try again." }
    $subscriptions = $subscriptionsJson | ConvertFrom-Json
    if (-not $subscriptions) { throw "No enabled subscriptions found. Run 'az login' with your student account." }
    Write-Host "Available Azure subscriptions (copy the ID of your own subscription):"
    foreach ($subscription in $subscriptions) {
        Write-Host "  $($subscription.name): $($subscription.id)"
    }
    $settings.SubscriptionId = Read-RequiredSetting "Subscription ID" $settings.SubscriptionId
    $settings.ResourceGroup = Read-RequiredSetting "Resource group" $settings.ResourceGroup
    $settings.ServerName = Read-RequiredSetting "SQL server name (not the full hostname)" $settings.ServerName
    $settings.DatabaseName = Read-RequiredSetting "Database name" $settings.DatabaseName
    $settings.RuleName = Read-RequiredSetting "Firewall rule name (use a unique name for your laptop)" $settings.RuleName
}
foreach ($key in @($settings.Keys)) { $settings[$key] = $settings[$key].Trim() }
$subscriptionGuid = [guid]::Empty
if (-not [guid]::TryParse($settings.SubscriptionId, [ref]$subscriptionGuid)) {
    throw "Subscription ID must be a GUID. Run with -Configure to choose your subscription."
}
$SubscriptionId = $settings.SubscriptionId
$ResourceGroup = $settings.ResourceGroup
$ServerName = $settings.ServerName
$DatabaseName = $settings.DatabaseName
$RuleName = $settings.RuleName

$subscriptionName = az account show --subscription $SubscriptionId --query name -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionName)) {
    throw "Cannot access subscription '$SubscriptionId'. Run 'az login' with the correct account."
}
$serverHost = az sql server show --subscription $SubscriptionId -g $ResourceGroup -n $ServerName --query fullyQualifiedDomainName -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverHost)) {
    throw "Cannot find SQL server '$ServerName' in the selected subscription/resource group. Check your settings and permissions."
}
$database = az sql db show --subscription $SubscriptionId -g $ResourceGroup -s $ServerName -n $DatabaseName --query name -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($database)) {
    throw "Cannot find database '$DatabaseName' on '$ServerName'. Create the database first or correct your settings."
}
Write-Host "Target subscription: $subscriptionName ($SubscriptionId)"
Write-Host "Resource group: $ResourceGroup; SQL server: $ServerName; database: $DatabaseName; rule: $RuleName"
Write-Host "Only this named firewall rule will be updated. Every other rule will be preserved."
if ($needsSetup) {
    $confirmation = Read-Host "Save these settings locally and update this laptop's firewall rule? [y/N]"
    if ($confirmation -notmatch '^(?i:y|yes)$') {
        Write-Host "Cancelled. No settings or Azure resources were changed."
        return
    }
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host "Saved local settings to '$configPath' (Git-ignored; no credentials stored)."
}

$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 15).Trim()
$parsedIp = $null
if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or
    -not [System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) {
    throw "Could not determine a valid public IPv4 address (got '$ip')."
}

Write-Host "Setting firewall rule '$RuleName' on '$ServerName' to $ip ..."

$rulesJson = az sql server firewall-rule list --subscription $SubscriptionId -g $ResourceGroup -s $ServerName --query "[].name" -o json
if ($LASTEXITCODE -ne 0) { throw "Failed to read firewall rules. Are you signed in with 'az login'?" }
$ruleNames = $rulesJson | ConvertFrom-Json

if ($ruleNames -contains $RuleName) {
    az sql server firewall-rule update --subscription $SubscriptionId -g $ResourceGroup -s $ServerName -n $RuleName `
        --start-ip-address $ip --end-ip-address $ip --output none
} else {
    az sql server firewall-rule create --subscription $SubscriptionId -g $ResourceGroup -s $ServerName -n $RuleName `
        --start-ip-address $ip --end-ip-address $ip --output none
}
if ($LASTEXITCODE -ne 0) { throw "Failed to update the firewall rule." }

Write-Host "Laptop rule allows $ip; all other rules were preserved (changes can take up to a few minutes to apply)."

if ($SkipDatabaseWarmup) {
    Write-Host "Done. Database warm-up was skipped."
    return
}

Add-Type -AssemblyName System.Data
$accessToken = az account get-access-token --subscription $SubscriptionId --resource "https://database.windows.net/" --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
    throw "Firewall updated, but could not get a SQL access token. Run 'az login' and try again."
}

$connectionString = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$connectionString["Data Source"] = "tcp:$serverHost,1433"
$connectionString["Initial Catalog"] = $DatabaseName
$connectionString["Encrypt"] = $true
$connectionString["TrustServerCertificate"] = $false
$connectionString["Connect Timeout"] = 15
$connectionString["ConnectRetryCount"] = 0
# Closing the probe must release the session so normal auto-pause remains possible.
$connectionString["Pooling"] = $false

$maxAttempts = 12
$transientErrors = @(-2, 40613, 40615, 40197, 40501, 10928, 10929, 49918, 49919, 49920)
try {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "Waking database '$DatabaseName' (attempt $attempt/$maxAttempts) ..."
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $command = $null
        try {
            $connection.ConnectionString = $connectionString.ConnectionString
            $connection.AccessToken = $accessToken
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT 1"
            $command.CommandTimeout = 5
            if ($command.ExecuteScalar() -ne 1) {
                throw "Database readiness query returned an unexpected result."
            }
            Write-Host "Done. Database '$DatabaseName' is ready. Serverless and auto-pause settings are unchanged."
            break
        } catch [System.Data.SqlClient.SqlException] {
            if ($_.Exception.Number -notin $transientErrors -or $attempt -eq $maxAttempts) {
                throw "Firewall updated, but database warm-up failed: $($_.Exception.Message)"
            }
            Write-Warning "Database not ready yet (SQL error $($_.Exception.Number)): $($_.Exception.Message). Retrying in 10 seconds."
        } finally {
            if ($null -ne $command) { $command.Dispose() }
            $connection.Dispose()
        }
        Start-Sleep -Seconds 10
    }
} finally {
    $accessToken = $null
}
