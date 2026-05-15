# Copilot Instructions

## Project Overview

This is a **reference implementation** showing how to package a 3rd-party marketplace virtual machine image as an **Azure Managed Application** published to the Azure Service Catalog. It uses **RHEL 9 pay-as-you-go** as the concrete example image, but the patterns apply to any Azure Marketplace VM image.

The repo consists of ARM template files and deployment scripts — there is no application source code, build system, or test framework. It focuses purely on the packaging and publishing workflow for marketplace VM images.

## Architecture

The managed application follows the [Azure Service Catalog managed app structure](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/publish-service-catalog-app):

- **`mainTemplate.json`** — ARM deployment template. Provisions: NSG, VNet/subnet, public IP, NIC, and a marketplace VM image (example: RedHat RHEL `96-gen2` PAYGO). This can be adapted for any Azure Marketplace image.
- **`createUiDefinition.json`** — Azure Portal wizard UI for deployment parameters.
- **`viewDefinition.json`** — Post-deployment overview blade in the Portal.
- **`parameters.json`** — Sample parameters for validation and test deployments.

These three JSON files are packaged into `app.zip` and uploaded to a storage account to create the managed app definition.

## Deployment Scripts

Cross-platform scripts (`deploy.sh` for Bash, `deploy.ps1` for PowerShell) handle the full lifecycle. Both require the Azure CLI (`az`) and an authenticated session.

### Actions

| Action | What it does |
|--------|-------------|
| `validate` | Runs `az deployment group validate` against `mainTemplate.json` |
| `test` | Validates, then deploys real resources to a resource group |
| `package` | Zips `mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json` into `app.zip` |
| `publish` | Validates, packages, uploads to blob storage, creates the managed app definition |

### Running

```bash
# Validate only
./deploy.sh -a validate -g myResourceGroup

# Full publish
./deploy.sh -a publish -g myResourceGroup -s mystorageaccount
```

```powershell
# Validate only
.\deploy.ps1 -Action Validate -ResourceGroupName myResourceGroup

# Full publish
.\deploy.ps1 -Action Publish -ResourceGroupName myResourceGroup -StorageAccountName mystorageaccount
```

## Key Conventions

- **ARM API versions**: Network resources use `2025-07-01`, VMs use `2025-11-01`. Keep these consistent when adding resources.
- **Naming pattern**: Derived resources use `{vmName}-{suffix}` (e.g., `-vnet`, `-nsg`, `-nic`, `-pip`). Maintain this convention.
- **Authentication**: The template supports both SSH public key and password auth, controlled by the `authenticationType` parameter with a conditional `linuxConfiguration` block.
- **Default region**: `westeurope` in both deploy scripts.
- **ZIP size limit**: The packaged `app.zip` must stay under 120 MB (Azure Service Catalog constraint).
- **`app.zip` is gitignored** — it's a build artifact, not committed.

## Working with ARM Templates

When modifying `mainTemplate.json`:
- Ensure `createUiDefinition.json` outputs match `mainTemplate.json` parameters exactly.
- Use `dependsOn` with `resourceId()` references, not hardcoded strings.
- The `viewDefinition.json` is minimal — update it if adding user-visible outputs.
- Validate changes with `./deploy.sh -a validate -g <rg>` before committing.
