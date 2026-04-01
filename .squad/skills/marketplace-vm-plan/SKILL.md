---
name: "marketplace-vm-plan"
description: "Pattern for deploying Azure VMs from marketplace images with plan blocks in Bicep/ARM"
domain: "bicep, arm-templates, marketplace"
confidence: "high"
source: "earned — researched from Microsoft Learn docs and official examples"
tools:
  - name: "mslearn-microsoft_docs_search"
    description: "Search Azure docs for marketplace image patterns"
    when: "When looking up imageReference or plan block syntax"
  - name: "mslearn-microsoft_code_sample_search"
    description: "Search for ARM/Bicep code samples"
    when: "When looking for complete VM deployment examples"
---

## Context

When deploying Azure VMs from 3rd-party marketplace images (BYOS, ISV images, etc.), the ARM/Bicep resource definition must include a `plan` block in addition to the `imageReference`. This is required by:
- Azure deployment runtime (omission causes deployment failure)
- Marketplace certification policy 300.4.8 (for managed applications)

First-party platform images (e.g., Windows Server, Ubuntu from Canonical) do NOT require a plan block.

## Patterns

### 1. Plan Block Placement

The `plan` block is a **top-level property** of the VM resource, sibling of `properties`:

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location

  plan: {
    name: skuName        // matches imageReference.sku
    product: offerName   // matches imageReference.offer
    publisher: publisherName // matches imageReference.publisher
  }

  properties: {
    storageProfile: {
      imageReference: {
        publisher: publisherName
        offer: offerName
        sku: skuName
        version: 'latest'
      }
    }
    // ... other properties
  }
}
```

### 2. Field Mapping (Critical)

| plan field | maps to | example |
|-----------|---------|---------|
| `plan.publisher` | `imageReference.publisher` | `redhat` |
| `plan.product` | `imageReference.offer` | `rhel-byos` |
| `plan.name` | `imageReference.sku` | `rhel-lvm9-gen2` |

### 3. ARM/JSON Format

```json
{
  "type": "Microsoft.Compute/virtualMachines",
  "apiVersion": "2024-07-01",
  "name": "[parameters('vmName')]",
  "location": "[parameters('location')]",
  "plan": {
    "name": "[parameters('imageSku')]",
    "product": "[parameters('imageOffer')]",
    "publisher": "[parameters('imagePublisher')]"
  },
  "properties": {
    "storageProfile": {
      "imageReference": {
        "publisher": "[parameters('imagePublisher')]",
        "offer": "[parameters('imageOffer')]",
        "sku": "[parameters('imageSku')]",
        "version": "latest"
      }
    }
  }
}
```

### 4. Terms Acceptance (Pre-Deployment)

```bash
# Check plan info for any marketplace image
az vm image show --location <region> --urn <publisher>:<offer>:<sku>:latest

# Accept terms (once per subscription per SKU)
az vm image terms accept --publisher <publisher> --offer <offer> --plan <sku>
```

### 5. RHEL BYOS Specific Coordinates

| Field | Value |
|-------|-------|
| Publisher | `redhat` (always lowercase) |
| Offer | `rhel-byos` |
| SKU (RHEL 9 Gen2) | `rhel-lvm9-gen2` (verify with az cli) |
| Version | `latest` |

## Examples

### Complete RHEL 9 BYOS VM in Bicep

```bicep
@description('The name of the VM')
param vmName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VM size')
param vmSize string = 'Standard_D2s_v3'

@description('Admin username')
param adminUsername string

@description('SSH public key')
@secure()
param sshPublicKey string

var imageReference = {
  publisher: 'redhat'
  offer: 'rhel-byos'
  sku: 'rhel-lvm9-gen2'
  version: 'latest'
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location

  plan: {
    name: imageReference.sku
    product: imageReference.offer
    publisher: imageReference.publisher
  }

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: imageReference
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}
```

## Anti-Patterns

- **Omitting plan block for marketplace images** → deployment will fail with "MarketplacePurchaseEligibilityFailed" or similar
- **Using `plan` for first-party images** → deployment may fail; plan is only for 3rd-party/BYOS
- **Mismatched plan/imageReference values** → plan.product must equal imageReference.offer, plan.name must equal imageReference.sku
- **Hardcoding SKUs without verification** → SKU names change; always validate with `az vm image list-skus`
- **Forgetting terms acceptance** → programmatic deployment requires `az vm image terms accept` before first use
- **Using BYOS without Red Hat Cloud Access** → BYOS images are private offers; subscription must be enrolled
