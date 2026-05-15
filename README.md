# Azure Managed Application CI example: 3rd-Party Marketplace VM Image Packaging and Testing

This repository is a **reference implementation** showing how to package a 3rd-party marketplace virtual machine image as an Azure Service Catalog managed application. It demonstrates the complete workflow for packaging, publishing, and deploying a marketplace VM image through Azure's managed application framework.

The repo uses **Red Hat Enterprise Linux (RHEL) 9 pay-as-you-go** as a concrete example of a 3rd-party marketplace image. The patterns and templates here apply to any Azure Marketplace VM image you wish to package and publish to Service Catalog.

It is built around Azure Managed Applications and follows the Microsoft guidance for [publishing service catalog managed apps](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/publish-service-catalog-app).

## Project overview

This project demonstrates how to package and publish a managed application that deploys a 3rd-party marketplace VM image (in this case, **RHEL 9 PAYGO**) along with its required networking resources:

- A **marketplace VM image** (example: RHEL 9 PAYGO)
- A **virtual network**
- A **subnet**
- A **network security group (NSG)**
- A **static Standard public IP**
- A **network interface (NIC)**

You can use the repo in two ways:

1. **Deploy the ARM template directly** for validation and smoke testing — useful during development and customization.
2. **Package and publish the managed application** to Azure Service Catalog, then deploy it from the Azure Portal or the Azure CLI — the production publishing flow.

To adapt this for a different marketplace VM image, modify the `imageReference` in `mainTemplate.json` and update `createUiDefinition.json` and documentation accordingly.

## Architecture / what gets deployed

`mainTemplate.json` provisions the following Azure resources:

| Resource | Type | Notes |
| --- | --- | --- |
| Network security group | `Microsoft.Network/networkSecurityGroups` | Includes an inbound SSH rule on TCP/22 |
| Virtual network | `Microsoft.Network/virtualNetworks` | Default address space `10.0.0.0/16` |
| Subnet | Child resource of the VNet | Default subnet prefix `10.0.0.0/24` |
| Public IP | `Microsoft.Network/publicIPAddresses` | Standard SKU, static allocation |
| Network interface | `Microsoft.Network/networkInterfaces` | Connected to the subnet and public IP |
| Virtual machine | `Microsoft.Compute/virtualMachines` | RHEL 9 PAYGO image |

### Authentication options

The template supports two Linux authentication modes:

- **`sshPublicKey`** — recommended for most scenarios. The public key is written into `~/.ssh/authorized_keys` for the admin user.
- **`password`** — enabled by setting `authenticationType=password` and passing the password through `adminPasswordOrKey`.

The ARM template uses a conditional `linuxConfiguration` block so only the selected auth model is applied.

### Naming convention

Derived resource names follow the pattern:

- `{vmName}-vnet`
- `{vmName}-nsg`
- `{vmName}-nic`
- `{vmName}-pip`

That means a VM named `rhel9-demo` will typically produce resources such as `rhel9-demo-vnet` and `rhel9-demo-nsg`.

## Prerequisites

Before you use these templates, make sure you have:

- An **Azure subscription**
- The **Azure CLI** installed and authenticated (`az login`)
- Permission to create resource groups and deploy resources in the target subscription
- **PowerShell** (optional) if you want to use `deploy.ps1`

Useful checks:

```bash
az version
az account show --output table
```

### Marketplace image terms

For many 3rd-party marketplace VM images, the subscription must accept the image terms before the first deployment.

```bash
az vm image terms accept --publisher RedHat --offer RHEL --plan 96-gen2
```

RHEL PAYGO images may not require an explicit acceptance step in every subscription, but many other marketplace images do. If you adapt this repo to a different image, verify the image terms requirements before testing deployments.

## Template files

| File | Purpose |
| --- | --- |
| `mainTemplate.json` | Main ARM template that deploys the VM and networking stack |
| `createUiDefinition.json` | Azure Portal deployment wizard for the managed application |
| `viewDefinition.json` | Post-deployment overview blade shown in the Portal |
| `parameters.json` | Sample parameter file for direct validation and test deployments |
| `deploy.sh` | Bash helper script for validate, test, package, and publish operations |
| `deploy.ps1` | PowerShell helper script for the same lifecycle |

### ARM API versions used

The current template uses:

- **Network resources:** `2023-11-01`
- **Virtual machine:** `2024-07-01`

## Testing the UI definition

You can test `createUiDefinition.json` without publishing anything by using the Azure Portal sandbox:

- Sandbox URL: <https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/SandboxBlade>

### How to test it

1. Open the sandbox link.
2. Copy the contents of `createUiDefinition.json`.
3. Paste the JSON into the sandbox.
4. Preview the wizard and validate the inputs, steps, defaults, and output mappings.

This is the fastest way to verify the deployment experience before packaging the managed application.

## Deploying the ARM template directly (without managed app)

For fast iteration, deploy `mainTemplate.json` directly into a resource group.

### Validate first

```bash
RG_NAME="rg-rhel9-direct"
LOCATION="westeurope"

az group create --name "$RG_NAME" --location "$LOCATION"
az deployment group validate \
  --resource-group "$RG_NAME" \
  --template-file mainTemplate.json \
  --parameters @parameters.json
```

### Deploy with `az deployment group create`

```bash
RG_NAME="rg-rhel9-direct"
DEPLOYMENT_NAME="rhel9-direct-$(date +%Y%m%d%H%M%S)"

az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RG_NAME" \
  --template-file mainTemplate.json \
  --parameters @parameters.json
```

### Override parameters inline

```bash
az deployment group create \
  --name rhel9-direct-password \
  --resource-group "$RG_NAME" \
  --template-file mainTemplate.json \
  --parameters @parameters.json \
  --parameters vmName=rhel9-password-demo \
               authenticationType=password \
               adminPasswordOrKey='StrongPassw0rd123!'
```

> `parameters.json` is a sample file. Update the SSH public key or password values before using it for a real deployment.

## Packaging the managed application

Azure Service Catalog expects a ZIP package with the managed application files at the **root** of the archive.

This repo packages:

- `mainTemplate.json`
- `createUiDefinition.json`
- `viewDefinition.json`

into:

- `app.zip`

The package must remain under the **120 MB** limit for service catalog managed application definitions.

### Package with Bash

```bash
./deploy.sh -a package -g rg-rhel9-managedapp
```

### Package with PowerShell

```powershell
.\deploy.ps1 -Action Package -ResourceGroupName rg-rhel9-managedapp
```

> The current scripts require a resource group argument even for `package`, because the scripts parse `-g` / `-ResourceGroupName` as mandatory input.

## Publishing to the Service Catalog

The publish flow in this repo is script-driven.

### What the publish action does

1. Validates `mainTemplate.json`
2. Packages the three JSON files into `app.zip`
3. Uploads `app.zip` to Azure Blob Storage
4. Creates the managed application definition in a resource group

### Required permissions

To publish successfully, your identity should be able to:

- Create or update **resource groups**
- Create or update a **storage account** and **blob container**
- Upload blobs to the storage account
- Create a **managed application definition**
- Read the current signed-in user or principal information from Microsoft Entra ID
- Read the Azure built-in role definition used for the managed resource group authorization

In practice, that usually means a deployment/admin identity with sufficient subscription or resource-group permissions, plus blob data access on the storage account when using `--auth-mode login`.

### Publish with Bash

```bash
./deploy.sh \
  -a publish \
  -g rg-rhel9-managedapp \
  -l westeurope \
  -s myuniquestorageacct123
```

### Publish with PowerShell

```powershell
.\deploy.ps1 \
  -Action Publish \
  -ResourceGroupName rg-rhel9-managedapp \
  -Location westeurope \
  -StorageAccountName myuniquestorageacct123
```

The scripts create the managed app definition with the signed-in user as the authorized managing principal and the **Owner** role on the managed resource group.

## Deploying from the Service Catalog

Once the definition is published, you can deploy an instance of the managed application either from the Azure Portal or from the Azure CLI.

### Deploy from the Azure Portal

1. Open the Azure Portal.
2. Go to **Create a resource**.
3. Open **Service Catalog**.
4. Find the managed application definition (for example, **RHEL 9 PAYGO VM**).
5. Select it and walk through the deployment wizard.
6. Review and create the managed application instance.

If other users need to see the definition, grant them at least **Reader** access on the managed application definition scope.

### Deploy from the Azure CLI

Create or identify:

- A resource group where the **managed application instance** will live
- A **managed resource group name** that Azure will create automatically for the deployed resources
- The managed application definition ID

Example:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="westeurope"
INSTANCE_RG="rg-rhel9-app-instance"
MANAGED_RG="rg-rhel9-app-managed"
DEF_RG="rg-rhel9-managedapp"
DEF_NAME="rhel9-managed-app"
APP_NAME="rhel9-managed-instance"

az group create --name "$INSTANCE_RG" --location "$LOCATION"
# Do not create "$MANAGED_RG" ahead of time; Azure creates the managed resource group during deployment.

DEF_ID=$(az managedapp definition show \
  --resource-group "$DEF_RG" \
  --name "$DEF_NAME" \
  --query id \
  --output tsv)

az managedapp create \
  --kind ServiceCatalog \
  --name "$APP_NAME" \
  --location "$LOCATION" \
  --resource-group "$INSTANCE_RG" \
  --managed-rg-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$MANAGED_RG" \
  --managedapp-definition-id "$DEF_ID" \
  --parameters @parameters.json
```

This creates a managed application instance backed by the published Service Catalog definition. The managed resource group must not already exist before `az managedapp create` runs.

## Testing the managed application end to end

Publishing to Azure Service Catalog and then deploying from that catalog is a recommended way to test the full managed application lifecycle before publishing more broadly, including Azure Marketplace scenarios.

A practical end-to-end test looks like this:

1. Validate the template
2. Package `app.zip`
3. Publish the definition to Service Catalog
4. Deploy one instance from the Portal or `az managedapp create`
5. Verify the managed resource group contains the VM, NIC, IP, VNet, subnet, and NSG
6. Delete the test instance and, if needed, the definition resource group

Helpful verification commands:

```bash
az managedapp list --output table
az resource list --resource-group "$MANAGED_RG" --output table
az vm list --resource-group "$MANAGED_RG" --output table
```

## Deployment scripts reference

Both scripts support the same lifecycle.

### Actions

| Action | What it does |
| --- | --- |
| `validate` / `Validate` | Runs `az deployment group validate` against `mainTemplate.json` |
| `test` / `Test` | Validates and then deploys `mainTemplate.json` directly to a resource group |
| `package` / `Package` | Builds `app.zip` from `mainTemplate.json`, `createUiDefinition.json`, and `viewDefinition.json` |
| `publish` / `Publish` | Validates, packages, uploads `app.zip`, and creates the managed app definition |
| `all` / `All` | Runs validate + package + publish |

> `all` does **not** run the direct test deployment in the current implementation.

### Bash script parameters (`deploy.sh`)

| Flag | Meaning | Default |
| --- | --- | --- |
| `-g` | Resource group name | Required |
| `-l` | Azure region | `westeurope` |
| `-s` | Storage account name | Required for `publish` |
| `-c` | Blob container name | `appcontainer` |
| `-n` | Managed app definition name | `rhel9-managed-app` |
| `-d` | Managed app definition display name | `RHEL 9 PAYGO VM` |
| `-e` | Managed app definition description | Built-in default |
| `-k` | Lock level | `ReadOnly` |
| `-a` | Action (`validate`, `test`, `package`, `publish`, `all`) | `all` |
| `-h` | Help | n/a |

Examples:

```bash
./deploy.sh -a validate -g rg-rhel9-managedapp
./deploy.sh -a test -g rg-rhel9-managedapp
./deploy.sh -a package -g rg-rhel9-managedapp
./deploy.sh -a publish -g rg-rhel9-managedapp -s myuniquestorageacct123
```

### PowerShell parameters (`deploy.ps1`)

| Parameter | Meaning | Default |
| --- | --- | --- |
| `-ResourceGroupName` | Resource group name | Required |
| `-Location` | Azure region | `westeurope` |
| `-StorageAccountName` | Storage account name | Required for `Publish` |
| `-StorageContainerName` | Blob container name | `appcontainer` |
| `-AppDefinitionName` | Managed app definition name | `rhel9-managed-app` |
| `-AppDefinitionDisplayName` | Managed app definition display name | `RHEL 9 PAYGO VM` |
| `-AppDefinitionDescription` | Managed app definition description | Built-in default |
| `-LockLevel` | `ReadOnly` or `CanNotDelete` | `ReadOnly` |
| `-Action` | `Validate`, `Test`, `Package`, `Publish`, `All` | `All` |

Examples:

```powershell
.\deploy.ps1 -Action Validate -ResourceGroupName rg-rhel9-managedapp
.\deploy.ps1 -Action Test -ResourceGroupName rg-rhel9-managedapp
.\deploy.ps1 -Action Package -ResourceGroupName rg-rhel9-managedapp
.\deploy.ps1 -Action Publish -ResourceGroupName rg-rhel9-managedapp -StorageAccountName myuniquestorageacct123
```

## CI/CD (GitHub Actions)

This repository uses **`.github/workflows/ci.yml`** for CI.

### What the workflow does

The workflow validates the managed application package end to end:

1. Runs **ARM-TTK validation** against `mainTemplate.json`, `createUiDefinition.json`, and the marketplace package structure
2. Runs **ARM deployment validation** with generated test parameters
3. Builds `app.zip` and verifies both the **size limit** and the **expected root-level contents**
4. Runs an **integration test** that publishes the package to Service Catalog, deploys a managed application instance, verifies the expected resources, and then cleans everything up
5. Purges soft-deleted **Key Vault**, **App Configuration**, and **Cognitive Services** resources during cleanup when they appear in the managed resource inventory

### Workflow triggers

- **Push** when `mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json`, `parameters.json`, `deploy.sh`, `deploy.ps1`, or `.github/workflows/ci.yml` changes
- **Monthly schedule** at `0 3 1 * *`
- **Manual trigger** (`workflow_dispatch`)

### Required secrets / identity inputs

The workflow requires:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Use **OIDC / workload identity federation** for GitHub Actions rather than storing a client secret. That means:

- create a Microsoft Entra application or user-assigned managed identity
- configure a federated credential that trusts the GitHub repository/workflow
- grant the identity the Azure roles needed for validation, packaging, deployment, and cleanup

The CI identity should have, at minimum:

- **Contributor** on the subscription or target resource group scope
- Permission to read Microsoft Entra service principal details used by `az ad sp show`
- If templates include Key Vault resources, **Key Vault Contributor** plus permission to purge soft-deleted vaults

## Reference documentation

Microsoft Learn references used for this repo:

- [Plan a solution template for an Azure application offer](https://learn.microsoft.com/en-us/partner-center/marketplace-offers/plan-azure-app-solution-template)
- [Configure a solution template plan](https://learn.microsoft.com/en-us/partner-center/marketplace-offers/azure-app-solution)
- [Quickstart: Create and publish an Azure Managed Application definition](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/publish-service-catalog-app)
- [Azure Managed Applications overview](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/overview)
- [Use ARM template test toolkit](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/test-toolkit)
- [CreateUiDefinition overview](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/create-uidefinition-overview)

## Notes

- Azure Managed Applications require the package files to be at the **root** of the ZIP archive.
- The Portal UI (`createUiDefinition.json`) must map outputs cleanly to the parameters expected by `mainTemplate.json`.
- `viewDefinition.json` is intentionally minimal and can be expanded later if you want richer post-deployment views.
