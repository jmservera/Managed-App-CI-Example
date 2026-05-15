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

---

## 2026-05-15 — GitHub Actions CI/CD Workflow for Managed Application (Naomi)

**Status:** Implemented  
**Scope:** Automated testing and publishing of Azure Managed Application through GitHub Actions

### Decision

Create a single GitHub Actions workflow at `.github/workflows/ci.yml` that validates, packages, integration-tests, and cleans up the Azure Managed Application end to end. The workflow should:

1. **Single job architecture:** All stages share generated names and state for reliable, repeatable smoke tests
2. **OIDC-only authentication:** Use `azure/login@v2` with `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` secrets (no PAT/SPN credentials)
3. **ARM-TTK validation:** Install from official GitHub release; test against staging folder with both `mainTemplate.json` and `maintemplate.json` alias for Linux CI compatibility
4. **Package validation:** Verify `app.zip` contains root-level `mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json`; enforce 120 MB service catalog limit
5. **Integration testing:** Publish package to temporary storage account, create managed app definition, deploy managed app instance, verify VM plus derived resources (`-vnet`, `-nsg`, `-nic`, `-pip`)
6. **Soft-delete cleanup:** Use `if: always()` with extensible case dispatcher to purge soft-deleted resources (Key Vault, App Configuration, Cognitive Services)

### Rationale

- Repeatable smoke tests exercise the full managed app lifecycle, not just static template validation
- OIDC eliminates credential management complexity in CI/CD
- Cleanup in same job with `if: always()` reduces resource leakage risk from failed deployments
- Extensible purge dispatcher provides foundation for future soft-delete-capable resources
- Staging folder approach preserves required managed app package filenames while enabling Linux CI

### Consequences

- Workflow serves as authoritative validation gate for ARM templates and deployment packaging
- GitHub repository requires OIDC federated identity and Azure federated credential setup
- Temporary storage account created during workflow is cleaned up post-publish
- Managed app definitions and instances are cleaned up post-verification

**References:** `.squad/decisions/inbox/naomi-cicd-workflow.md`, `.squad/skills/managed-app-ci-workflow/SKILL.md`

---

## 2026-05-15 — README Documentation for Managed Application Operations (Holden)

**Status:** Implemented  
**Scope:** Comprehensive operational documentation for managed application users and maintainers

### Decision

Document the managed application architecture, deployment workflows, and CI/CD pipeline in root-level `README.md`. The documentation should cover:

1. **Architecture overview:** Managed application structure (mainTemplate, createUiDefinition, viewDefinition)
2. **Image reference:** RHEL 9 PAYGO configuration and marketplace details
3. **Direct deployment:** How to validate, test, and package using local scripts (deploy.sh, deploy.ps1)
4. **Service Catalog publishing:** Steps for uploading to storage account and creating managed app definition
5. **Portal testing:** UI sandbox verification of createUiDefinition
6. **CI/CD pipeline:** Document expected workflow path (`.github/workflows/ci.yml`), OIDC authentication setup, ARM-TTK validation, deployment verification, and cleanup
7. **Manual operations:** Copy-paste Azure CLI commands for common tasks

Document against expected workflow path `.github/workflows/ci.yml` even though delivery is concurrent with Naomi's CI implementation.

### Rationale

- User explicitly requested GitHub Actions guidance as part of top-level documentation
- Capturing workflow path, trigger model, OIDC expectations, and validation stages keeps operational documentation aligned with intended architecture
- Single source of truth for operators using either direct scripts or CI/CD workflows
- Defers detailed CI internals to workflow file itself; README surfaces only necessary operator context

### Consequences

- README becomes primary entry point for users deploying managed application
- Operators can follow copy-paste commands for both manual and automated workflows
- Explicit documentation of ARM vs. Service Catalog deployment differences reduces confusion
- README references expected CI workflow path; CI implementation updates will require README alignment

**References:** `.squad/decisions/inbox/holden-readme.md`
