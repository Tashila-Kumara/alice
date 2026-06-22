#Requires -Version 5.1

param (
    [Parameter(Mandatory = $true)]
    [string]$UserName,

    [ValidateSet('Basic', 'S0', 'S1', 'S2', 'S3', 'P1', 'P2', 'GP_Gen5_2', 'GP_Gen5_4')]
    [string]$SqlTier,

    [string]$Location,

    [string]$DatabaseName,
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function ConvertFrom-SecureStringPlain {
    param([Security.SecureString]$Secure)

    if ($null -eq $Secure) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-UserSegment {
    param([string]$RawUserName)

    $segment = ($RawUserName.Trim().ToLower() -replace '[^a-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($segment)) {
        Write-ErrorMessage 'Username is empty or invalid after sanitization.'
    }

    return $segment
}

function ConvertTo-AzureResourceGroupName {
    param([string]$Name)

    $sanitized = $Name.ToLower() -replace '[^a-z0-9_().-]', '-'
    $sanitized = ($sanitized -replace '-{2,}', '-').Trim('.', '-')

    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        Write-ErrorMessage 'Resource group name is invalid after sanitization.'
    }

    if ($sanitized.Length -gt 90) {
        $sanitized = $sanitized.Substring(0, 90).TrimEnd('.', '-')
    }

    return $sanitized
}

function ConvertTo-AzureSqlServerName {
    param([string]$Name)

    $sanitized = $Name.ToLower() -replace '[^a-z0-9-]', '-'
    $sanitized = ($sanitized -replace '-{2,}', '-').Trim('-')

    if ($sanitized.Length -gt 63) {
        $sanitized = $sanitized.Substring(0, 63).Trim('-')
    }

    if ($sanitized.Length -lt 3) {
        Write-ErrorMessage 'SQL server name is shorter than 3 characters after sanitization.'
    }

    return $sanitized
}

function ConvertTo-AzureSqlDatabaseName {
    param([string]$Name)

    $sanitized = $Name.ToLower() -replace '[^a-z0-9_-]', '-'
    $sanitized = ($sanitized -replace '-{2,}', '-').Trim('-')

    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        Write-ErrorMessage 'Database name is invalid after sanitization.'
    }

    if ($sanitized.Length -gt 128) {
        $sanitized = $sanitized.Substring(0, 128).Trim('-')
    }

    return $sanitized
}

function Escape-EnvDoubleQuotedValue {
    param([string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Get-ProjectRootPath {
    param([string]$ProvidedRoot)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedRoot)) {
        return (Resolve-Path -Path $ProvidedRoot).Path
    }

    $fromRepoSkill = Join-Path $PSScriptRoot '../../..'
    if (Test-Path $fromRepoSkill) {
        $resolved = Resolve-Path -Path $fromRepoSkill
        if (Test-Path (Join-Path $resolved.Path '.git')) {
            return $resolved.Path
        }
    }

    $cwd = (Get-Location).Path
    if (Test-Path (Join-Path $cwd '.git')) {
        return $cwd
    }

    Write-ErrorMessage 'Could not resolve project root. Pass -ProjectRoot with the absolute repository path.'
}

function Test-AzureSqlServerNameAvailable {
    param(
        [string]$ServerName,
        [string]$RegionLocation
    )

    $result = Test-AzSqlServerNameAvailability -Name $ServerName -Location $RegionLocation
    return $result.Available
}

function Select-MenuOption {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue
    }

    if ($null -eq $Options -or $Options.Count -eq 0) {
        Write-ErrorMessage "No options available for $Title."
    }

    Write-Host ''
    Write-Host $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Options[$i])
    }

    while ($true) {
        $choiceInput = Read-Host "Select option number (1-$($Options.Count))"
        $parsedChoice = 0
        if ([int]::TryParse($choiceInput, [ref]$parsedChoice) -and $parsedChoice -ge 1 -and $parsedChoice -le $Options.Count) {
            return $Options[$parsedChoice - 1]
        }

        Write-Host 'Invalid selection. Enter a valid number from the list.' -ForegroundColor Yellow
    }
}

function Confirm-Deployment {
    param(
        [string]$SubscriptionName,
        [string]$SubscriptionId,
        [string]$Region,
        [string]$Tier,
        [string]$ResourceGroupName,
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$SqlAdminLogin,
        [string]$EnvFilePath,
        [string]$PublicIp
    )

    Write-Host ''
    Write-Host '--- Deployment summary ---'
    Write-Host "Subscription : $SubscriptionName ($SubscriptionId)"
    Write-Host "Region       : $Region"
    Write-Host "Service tier : $Tier"
    Write-Host "Resource grp : $ResourceGroupName"
    Write-Host "SQL server   : $ServerName"
    Write-Host "Database     : $DatabaseName"
    Write-Host "SQL admin    : $SqlAdminLogin"
    Write-Host "Env file     : $EnvFilePath"
    Write-Host "Firewall IP  : $PublicIp"
    Write-Host '--------------------------'
    Write-Host ''

    while ($true) {
        $answer = (Read-Host 'Proceed with deployment? (Y/N)').Trim()
        switch ($answer.ToUpperInvariant()) {
            { $_ -in 'Y', 'YES' } { return $true }
            { $_ -in 'N', 'NO' } {
                Write-Host 'Deployment cancelled by user.'
                exit 0
            }
            default {
                Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
            }
        }
    }
}

# --- Pre-flight ---
Write-Host 'Running pre-flight checks...'

if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Azure PowerShell module ('Az') is missing. Installing for current user..."
    try {
        Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
    catch {
        Write-ErrorMessage "Failed to install Az module. Run 'Install-Module Az -Scope CurrentUser' manually."
    }
}

Import-Module Az -ErrorAction Stop

$context = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $context) {
    Write-ErrorMessage "No active Azure session. Run 'Connect-AzAccount' in your terminal, then retry."
}

$tierOptions = @('Basic', 'S0', 'S1', 'S2', 'S3', 'P1', 'P2', 'GP_Gen5_2', 'GP_Gen5_4')
$SqlTier = Select-MenuOption -Title 'Select Azure SQL service tier' -Options $tierOptions -CurrentValue $SqlTier

$allLocations = Get-AzLocation
$sqlLocations = $allLocations |
    Where-Object { $_.Providers -contains 'Microsoft.Sql' } |
    Select-Object -ExpandProperty Location -Unique |
    Sort-Object

if ($sqlLocations.Count -eq 0) {
    Write-ErrorMessage 'No Azure regions with Microsoft.Sql provider were found in this subscription.'
}

$defaultLocationOptions = @('eastus', 'westus2', 'westeurope', 'southeastasia') |
    Where-Object { $sqlLocations -contains $_ }

$locationMenuOptions = if ($defaultLocationOptions.Count -gt 0) { $defaultLocationOptions } else { $sqlLocations }
$Location = Select-MenuOption -Title 'Select Azure region' -Options $locationMenuOptions -CurrentValue $Location

$resolvedLocationMatch = $allLocations | Where-Object {
    $_.Location -ieq $Location -or $_.DisplayName -ieq $Location
} | Select-Object -First 1

if (-not $resolvedLocationMatch) {
    Write-ErrorMessage "Location '$Location' is not available in this subscription."
}

$resolvedLocation = $resolvedLocationMatch.Location

$userSegment = Get-UserSegment -RawUserName $UserName
$dateSegment = Get-Date -Format 'yyyy_MM_dd'

$resourceGroupBase = "rg_sql_db_server_${userSegment}_${dateSegment}"
$serverBase = "sql_db_server_${userSegment}_${dateSegment}"
$databaseBase = if ([string]::IsNullOrWhiteSpace($DatabaseName)) {
    "sqldb_${userSegment}_${dateSegment}"
}
else {
    $DatabaseName
}

$resourceGroupName = ConvertTo-AzureResourceGroupName -Name $resourceGroupBase
$serverName = ConvertTo-AzureSqlServerName -Name ($serverBase -replace '_', '-')
$databaseName = ConvertTo-AzureSqlDatabaseName -Name ($databaseBase -replace '_', '-')
$envFileName = "$($serverBase).env"

$projectRootPath = Get-ProjectRootPath -ProvidedRoot $ProjectRoot
$envFilePath = Join-Path $projectRootPath $envFileName

if (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue) {
    Write-ErrorMessage "Resource group '$resourceGroupName' already exists. Use a different username or wait for a new date."
}

if (-not (Test-AzureSqlServerNameAvailable -ServerName $serverName -RegionLocation $resolvedLocation)) {
    Write-ErrorMessage "SQL server name '$serverName' is not available. Try a different username."
}

Write-Host 'Fetching your public IP address for firewall whitelisting...'
try {
    $publicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip
    Write-Host "Your public IP is: $publicIp"
}
catch {
    Write-ErrorMessage 'Failed to retrieve public IP address. Check your internet connection.'
}

$sqlAdminLogin = $userSegment

$confirmed = Confirm-Deployment `
    -SubscriptionName $context.Subscription.Name `
    -SubscriptionId $context.Subscription.Id `
    -Region $resolvedLocation `
    -Tier $SqlTier `
    -ResourceGroupName $resourceGroupName `
    -ServerName $serverName `
    -DatabaseName $databaseName `
    -SqlAdminLogin $sqlAdminLogin `
    -EnvFilePath $envFilePath `
    -PublicIp $publicIp

if (-not $confirmed) {
    exit 0
}

Write-Host "Enter SQL administrator password for login '$sqlAdminLogin' (input is masked):"
$sqlAdminPasswordSecure = Read-Host -AsSecureString

if ($null -eq $sqlAdminPasswordSecure -or $sqlAdminPasswordSecure.Length -eq 0) {
    Write-ErrorMessage 'SQL administrator password cannot be empty.'
}

$sqlAdminPasswordPlain = ConvertFrom-SecureStringPlain -Secure $sqlAdminPasswordSecure
$sqlCredential = New-Object System.Management.Automation.PSCredential($sqlAdminLogin, $sqlAdminPasswordSecure)

try {
    Write-Host "Creating resource group '$resourceGroupName' in '$resolvedLocation'..."
    $null = New-AzResourceGroup -Name $resourceGroupName -Location $resolvedLocation

    Write-Host "Deploying Azure SQL server '$serverName'..."
    $null = New-AzSqlServer `
        -ResourceGroupName $resourceGroupName `
        -ServerName $serverName `
        -Location $resolvedLocation `
        -SqlAdministratorCredentials $sqlCredential

    Write-Host 'Applying firewall rule for your local IP...'
    $null = New-AzSqlServerFirewallRule `
        -ResourceGroupName $resourceGroupName `
        -ServerName $serverName `
        -FirewallRuleName 'ClientLocalIP' `
        -StartIpAddress $publicIp `
        -EndIpAddress $publicIp

    $tierMap = @{
        Basic      = @{ Edition = 'Basic'; ServiceObjective = 'Basic' }
        S0         = @{ Edition = 'Standard'; ServiceObjective = 'S0' }
        S1         = @{ Edition = 'Standard'; ServiceObjective = 'S1' }
        S2         = @{ Edition = 'Standard'; ServiceObjective = 'S2' }
        S3         = @{ Edition = 'Standard'; ServiceObjective = 'S3' }
        P1         = @{ Edition = 'Premium'; ServiceObjective = 'P1' }
        P2         = @{ Edition = 'Premium'; ServiceObjective = 'P2' }
        GP_Gen5_2  = @{ Edition = 'GeneralPurpose'; ServiceObjective = 'GP_Gen5_2' }
        GP_Gen5_4  = @{ Edition = 'GeneralPurpose'; ServiceObjective = 'GP_Gen5_4' }
    }
    $tier = $tierMap[$SqlTier]

    Write-Host "Deploying Azure SQL database '$databaseName' (tier: $SqlTier)..."
    $null = New-AzSqlDatabase `
        -ResourceGroupName $resourceGroupName `
        -ServerName $serverName `
        -DatabaseName $databaseName `
        -Edition $tier.Edition `
        -RequestedServiceObjectiveName $tier.ServiceObjective

    $connectionString = "Server=tcp:${serverName}.database.windows.net,1433;Initial Catalog=${databaseName};Persist Security Info=False;User ID=${sqlAdminLogin};Password=${sqlAdminPasswordPlain};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $escapedConnectionString = Escape-EnvDoubleQuotedValue -Value $connectionString

    $envContent = @"
# Generated by azure_db_creator on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
AZURE_DB_CONNECTION_STRING="$escapedConnectionString"
"@

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Set-Content -Path $envFilePath -Value $envContent -Encoding utf8NoBOM
    }
    else {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($envFilePath, $envContent, $utf8NoBom)
    }

    Write-Host "RESOURCE_GROUP=$resourceGroupName"
    Write-Host "SQL_SERVER=$serverName"
    Write-Host "ENV_FILE=$envFilePath"
    Write-Host 'Deployment completed successfully.'
}
finally {
    if ($sqlAdminPasswordPlain) {
        $sqlAdminPasswordPlain = $null
    }
}
