# Decisions Log

**Project:** psa  
**Owner:** jmservera  

## 2026-04-01 — RHEL 9 BYOS Managed Application Image Reference (Holden)

**Status:** Proposed  
**Scope:** Partner managed application template for RHEL 9 BYOL VM deployment  

### Decision

Use the Red Hat BYOS Gold Image for RHEL 9:

| Field | Value |
|-------|-------|
| Publisher | `redhat` |
| Offer | `rhel-byos` |
| SKU | `rhel-lvm9-gen2` |
| Version | `latest` |
| URN | `redhat:rhel-byos:rhel-lvm9-gen2:latest` |

**Plan Block:**
```json
{
  "plan": {
    "name": "rhel-lvm9-gen2",
    "product": "rhel-byos",
    "publisher": "redhat"
  }
}
```

### Prerequisites

1. Partner's customer must have Red Hat Cloud Access enabled
2. Marketplace terms acceptance: `az vm image terms accept --publisher redhat --offer rhel-byos --plan rhel-lvm9-gen2`
3. BYOS images are private offers — subscription must be enrolled in Red Hat Cloud Access

### Rationale

- `rhel-byos` is the consistent offer name for all RHEL BYOS versions per Microsoft Learn
- SKU pattern `rhel-lvm{major}-gen2` is the Gen2 LVM variant
- Marketplace certification policy 300.4.8 requires plan object for marketplace images

### Consequences

- Managed app must document Red Hat Cloud Access prerequisite
- createUiDefinition.json should validate/inform about BYOS license requirement
- ARM template must include both `plan` and `imageReference` blocks

**References:** Microsoft Learn (BYOS, RHEL images), Azure Managed Applications, Marketplace certification policies

---

## 2026-04-01 — Marketplace VM Plan Block IaC Pattern (Naomi)

**Status:** Proposed  
**Scope:** Bicep/ARM template pattern for deploying VMs from Azure Marketplace images with plan blocks  

### Decision

The `plan` block must be a **sibling** of `properties`, not nested inside it. Plan fields must mirror imageReference fields:

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location

  plan: {
    name: imageReference.sku       // e.g., 'rhel-lvm9-gen2'
    product: imageReference.offer  // e.g., 'rhel-byos'
    publisher: imageReference.publisher // e.g., 'redhat'
  }

  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'redhat'
        offer: 'rhel-byos'
        sku: 'rhel-lvm9-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    osProfile: { ... }
    networkProfile: { ... }
  }
}
```

### Validation

Always validate exact SKU names before authoring:
```bash
az vm image list-skus --location <region> --publisher redhat --offer rhel-byos --output table
```

Terms acceptance:
```bash
az vm image terms accept --publisher redhat --offer rhel-byos --plan <sku>
```

### Rationale

- Certification policy 300.4.8 mandates plan block for marketplace images
- Omitting plan causes deployment failures for BYOS/3rd-party images
- First-party images (e.g., MicrosoftWindowsServer) do NOT need plan block

### Consequences

- All marketplace VM templates must follow this pattern
- SKU names must be validated against live marketplace before hardcoding

**References:** Microsoft Learn (templates/virtualmachines, certification policies), Marketplace programmatic deploy, Azure CLI findimage

**Reusable Asset:** `.squad/skills/marketplace-vm-plan/SKILL.md` created to encapsulate pattern
