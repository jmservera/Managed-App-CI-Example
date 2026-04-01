<#
.SYNOPSIS
    Validates, tests, packages, and publishes the RHEL 9 PAYGO managed application
    to an Azure Service Catalog.

.DESCRIPTION
    This script provides four operations:
      - Validate: Runs az deployment group validate against mainTemplate.json
      - Test:     Deploys mainTemplate.json directly to a resource group using parameters.json
      - Package:  Creates app.zip from the three managed app JSON files
      - Publish:  Uploads app.zip to a storage account and creates the managed app definition

.PARAMETER ResourceGroupName
    Target resource group for validation, test deployments, and the managed app definition.

.PARAMETER Location
    Azure region. Defaults to 'westeurope'.

.PARAMETER StorageAccountName
    Storage account for hosting app.zip. Must be globally unique, 3-24 lowercase alphanumeric chars.

.PARAMETER StorageContainerName
    Blob container name within the storage account. Defaults to 'appcontainer'.

.PARAMETER AppDefinitionName
    Display name for the managed application definition. Defaults to 'rhel9-managed-app'.

.PARAMETER AppDefinitionDisplayName
    User-friendly display name shown in the service catalog. Defaults to 'RHEL 9 PAYGO VM'.

.PARAMETER AppDefinitionDescription
    Description for the managed application definition.

.PARAMETER LockLevel
    Lock level for the managed resource group. ReadOnly or CanNotDelete. Defaults to 'ReadOnly'.

.PARAMETER Action
    Which operation to run: Validate, Test, Package, Publish, or All. Defaults to 'All'.

.EXAMPLE
    # Validate the template only
    .\deploy.ps1 -Action Validate -ResourceGroupName myRG

.EXAMPLE
    # Test deploy the template directly (creates real resources!)
    .\deploy.ps1 -Action Test -ResourceGroupName myRG

.EXAMPLE
    # Full publish flow: validate, package, upload, create definition
    .\deploy.ps1 -Action Publish -ResourceGroupName myRG -StorageAccountName mystgacct123
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$Location = "westeurope",

    [Parameter()]
    [string]$StorageAccountName = "",

    [Parameter()]
    [string]$StorageContainerName = "appcontainer",

    [Parameter()]
    [string]$AppDefinitionName = "rhel9-managed-app",

    [Parameter()]
    [string]$AppDefinitionDisplayName = "RHEL 9 PAYGO VM",

    [Parameter()]
    [string]$AppDefinitionDescription = "Deploys a Red Hat Enterprise Linux 9 pay-as-you-go virtual machine with networking stack.",

    [Parameter()]
    [ValidateSet("ReadOnly", "CanNotDelete")]
    [string]$LockLevel = "ReadOnly",

    [Parameter()]
    [ValidateSet("Validate", "Test", "Package", "Publish", "All")]
    [string]$Action = "All"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$TemplateFile = Join-Path $ScriptDir "mainTemplate.json"
$UiDefFile = Join-Path $ScriptDir "createUiDefinition.json"
$ViewDefFile = Join-Path $ScriptDir "viewDefinition.json"
$ParametersFile = Join-Path $ScriptDir "parameters.json"
$ZipFile = Join-Path $ScriptDir "app.zip"

# ─────────────────────────────────────────────
# Helper: coloured output
# ─────────────────────────────────────────────
function Write-Step { param([string]$Message) Write-Host "`n▶ $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "  ✔ $Message" -ForegroundColor Green }
function Write-Fail { param([string]$Message) Write-Host "  ✘ $Message" -ForegroundColor Red }

# ─────────────────────────────────────────────
# Step 1: Validate the ARM template
# ─────────────────────────────────────────────
function Invoke-Validate {
    Write-Step "Validating ARM template against resource group '$ResourceGroupName'..."

    # Ensure the resource group exists
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne "true") {
        Write-Host "  Resource group '$ResourceGroupName' not found — creating in '$Location'..."
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Ok "Resource group created."
    }

    az deployment group validate `
        --resource-group $ResourceGroupName `
        --template-file $TemplateFile `
        --parameters "@$ParametersFile" `
        --output table

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Template validation failed."
        exit 1
    }
    Write-Ok "Template validation succeeded."
}

# ─────────────────────────────────────────────
# Step 2: Test deploy (deploys real resources)
# ─────────────────────────────────────────────
function Invoke-TestDeploy {
    Write-Step "Test-deploying mainTemplate.json to resource group '$ResourceGroupName'..."
    Write-Host "  ⚠ This creates real Azure resources. Press Ctrl+C to abort." -ForegroundColor Yellow

    # Ensure resource group
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne "true") {
        az group create --name $ResourceGroupName --location $Location --output none
    }

    $deploymentName = "test-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    az deployment group create `
        --name $deploymentName `
        --resource-group $ResourceGroupName `
        --template-file $TemplateFile `
        --parameters "@$ParametersFile" `
        --output table

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Test deployment failed."
        exit 1
    }
    Write-Ok "Test deployment succeeded: $deploymentName"
}

# ─────────────────────────────────────────────
# Step 3: Package the managed app ZIP
# ─────────────────────────────────────────────
function Invoke-Package {
    Write-Step "Packaging managed application files into app.zip..."

    # Verify all required files exist
    foreach ($f in @($TemplateFile, $UiDefFile, $ViewDefFile)) {
        if (-not (Test-Path $f)) {
            Write-Fail "Required file not found: $f"
            exit 1
        }
    }

    # Remove existing zip to avoid stale content
    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    # Create ZIP — files must be at the root level of the archive
    Compress-Archive -Path $TemplateFile, $UiDefFile, $ViewDefFile -DestinationPath $ZipFile -CompressionLevel Optimal

    $zipSize = (Get-Item $ZipFile).Length
    $zipSizeMB = [math]::Round($zipSize / 1MB, 2)
    Write-Ok "Created app.zip ($zipSizeMB MB)"

    # Managed app ZIP has a 120 MB limit
    if ($zipSizeMB -gt 120) {
        Write-Fail "app.zip exceeds the 120 MB limit for service catalog managed applications."
        exit 1
    }
}

# ─────────────────────────────────────────────
# Step 4: Publish managed app definition
# ─────────────────────────────────────────────
function Invoke-Publish {
    Write-Step "Publishing managed application definition to service catalog..."

    if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
        Write-Fail "StorageAccountName is required for publishing. Use -StorageAccountName <name>."
        exit 1
    }

    # Ensure the ZIP exists
    if (-not (Test-Path $ZipFile)) {
        Write-Host "  app.zip not found — packaging first..."
        Invoke-Package
    }

    # Ensure resource group
    $rgExists = az group exists --name $ResourceGroupName 2>$null
    if ($rgExists -ne "true") {
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Ok "Resource group '$ResourceGroupName' created."
    }

    # Create storage account if it doesn't exist
    Write-Host "  Ensuring storage account '$StorageAccountName'..."
    $stgExists = az storage account check-name --name $StorageAccountName --query "nameAvailable" --output tsv 2>$null
    if ($stgExists -eq "true") {
        Write-Host "  Creating storage account '$StorageAccountName'..."
        az storage account create `
            --name $StorageAccountName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku Standard_LRS `
            --output none
        Write-Ok "Storage account created."
    } else {
        Write-Ok "Storage account '$StorageAccountName' already exists."
    }

    # Create blob container (idempotent)
    Write-Host "  Ensuring blob container '$StorageContainerName'..."
    az storage container create `
        --name $StorageContainerName `
        --account-name $StorageAccountName `
        --auth-mode login `
        --public-access blob `
        --output none 2>$null

    # Upload app.zip to blob storage
    Write-Host "  Uploading app.zip..."
    az storage blob upload `
        --account-name $StorageAccountName `
        --container-name $StorageContainerName `
        --auth-mode login `
        --name app.zip `
        --file $ZipFile `
        --overwrite `
        --output none

    Write-Ok "app.zip uploaded to storage."

    # Get the blob URL for the managed app definition
    $blobUri = az storage blob url `
        --account-name $StorageAccountName `
        --container-name $StorageContainerName `
        --auth-mode login `
        --name app.zip `
        --output tsv

    Write-Host "  Package URI: $blobUri"

    # Get current user's object ID and Owner role definition for --authorizations
    Write-Host "  Resolving current user principal and Owner role..."
    $userId = az ad signed-in-user show --query "id" --output tsv
    $roleId = az role definition list --name "Owner" --query "[0].name" --output tsv

    if ([string]::IsNullOrWhiteSpace($userId) -or [string]::IsNullOrWhiteSpace($roleId)) {
        Write-Fail "Could not resolve user ID or Owner role ID. Ensure you are signed in with 'az login'."
        exit 1
    }

    $authorization = "${userId}:${roleId}"
    Write-Host "  Authorization: $authorization"

    # Create the managed application definition
    Write-Host "  Creating managed app definition '$AppDefinitionName'..."
    az managedapp definition create `
        --name $AppDefinitionName `
        --location $Location `
        --resource-group $ResourceGroupName `
        --lock-level $LockLevel `
        --display-name $AppDefinitionDisplayName `
        --description $AppDefinitionDescription `
        --authorizations $authorization `
        --package-file-uri $blobUri `
        --output table

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to create managed app definition."
        exit 1
    }
    Write-Ok "Managed application definition '$AppDefinitionName' published to service catalog."
    Write-Host "`n  You can now deploy it from the Azure Portal:" -ForegroundColor Cyan
    Write-Host "    Portal → Create a resource → Service Catalog Managed Application → '$AppDefinitionDisplayName'"
}

# ─────────────────────────────────────────────
# Main — dispatch based on -Action
# ─────────────────────────────────────────────
switch ($Action) {
    "Validate" {
        Invoke-Validate
    }
    "Test" {
        Invoke-Validate
        Invoke-TestDeploy
    }
    "Package" {
        Invoke-Package
    }
    "Publish" {
        Invoke-Validate
        Invoke-Package
        Invoke-Publish
    }
    "All" {
        Invoke-Validate
        Invoke-Package
        Invoke-Publish
    }
}

Write-Host "`n✅ Done." -ForegroundColor Green
