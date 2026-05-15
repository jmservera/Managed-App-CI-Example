# Project Context

- **Owner:** jmservera
- **Project:** PSA — Azure architecture using Bicep with focus on security, reliability, and performance pillars
- **Stack:** Azure, Bicep, ARM, Azure Well-Architected Framework
- **Created:** 2026-04-01

# Project Context

- **Owner:** jmservera
- **Project:** PSA — Azure architecture using Bicep with focus on security, reliability, and performance pillars
- **Stack:** Azure, Bicep, ARM, Azure Well-Architected Framework
- **Created:** 2026-04-01

## Collaboration

### 2026-04-01 — RHEL 9 Marketplace Research Initiative

**Participants:** Holden (Lead), Naomi (Bicep Engineer), Scribe (Documentation)

**Cross-Agent Notes:**
- **Holden's image reference research** provided exact URN validation: `redhat:rhel-byos:rhel-lvm9-gen2:latest`
- Naomi's pattern templates and Bicep examples exemplify Holden's architectural plan block requirements
- Created reusable skill (`.squad/skills/marketplace-vm-plan/SKILL.md`) from synthesized findings
- Both agents' decision documents merged with deduplication into unified `decisions.md`

### 2026-05-15 — Managed Application CI/CD & Documentation Delivery

**Participants:** Naomi (CI/CD workflow), Holden (README documentation), Scribe (Orchestration)

**Cross-Agent Notes:**
- **Holden's README** documents expected workflow path `.github/workflows/ci.yml` before Naomi's delivery
- **Naomi's CI implementation** matches Holden's documented expectations: OIDC, ARM-TTK, integration deployment, soft-delete cleanup
- Both agents' decision notes merged into unified decisions log
- Orchestration logs created for both agents; session log documents concurrent delivery coordination

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-04-01 — PAYGO vs BYOS Trade-offs for RHEL 9

**Context:** Post-decision on originally BYOS-modeled managed app, coordinator pivoted to PAYGO.

**Key insight:** Licensing model choice has cascading implications on template complexity:
- **BYOS** requires `plan` block + marketplace terms acceptance + Red Hat Cloud Access enrollment + post-deploy subscription-manager registration. More gatekeeping, lower operational friction once licensed.
- **PAYGO** requires no `plan` block, no enrollment, no registration. VMs pre-entitled for RHUI. Simple deployment model, per-minute billing.

**Pattern:** When designing managed apps around VM images, establish licensing intent early. Switching between models requires touching all three template files (mainTemplate, createUiDefinition, viewDefinition) and image reference URN structure changes (e.g., publisher capitalization: `redhat` BYOS vs. `RedHat` PAYGO).

**Coordinator decision rationale:** PAYGO favors user velocity and reduces deployment friction at the cost of per-minute billing instead of pre-licensed cost control.

### 2026-04-01 — Marketplace VM with Plan Block (RHEL 9 BYOS)

**Context:** Research for partner managed app deploying RHEL 9 BYOL VM.

**Key patterns discovered:**
- Marketplace VM images that are 3rd-party or BYOS **require** a `plan` block at the resource level (sibling of `properties`, not inside it).
- `plan.product` must equal the `imageReference.offer` value.
- `plan.name` must equal the `imageReference.sku` value.
- `plan.publisher` must equal the `imageReference.publisher` value.
- Marketplace certification policy 300.4.8 mandates `plan` block when `imageReference` uses a marketplace image.

**RHEL BYOS image coordinates:**
- Publisher: `redhat` (lowercase always)
- Offer: `rhel-byos` (consistent across RHEL 7/8/9)
- SKU pattern: `rhel-lvm{major}{minor}` (e.g., `rhel-lvm87`) or `rhel-lvm{major}` for latest minor
- For RHEL 9 Gen2: SKU likely `rhel-lvm9-gen2` or `rhel-lvm90-gen2` — **must validate with `az vm image list-skus`**
- BYOS images are private offers requiring Red Hat Cloud Access enrollment

**BYOS licensing gotchas:**
- Terms must be accepted once per subscription per SKU: `az vm image terms accept`
- VMs are unentitled — must register with Red Hat Subscription-Manager post-deploy
- BYOS images are private; subscription must be enrolled via Red Hat Cloud Access
- Not available in CSP subscriptions

**Managed app requirements:**
- `mainTemplate.json` must include both `plan` and `imageReference`
- `createUiDefinition.json` should surface BYOS prerequisite info to end users

**Sources:**
- https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/byos
- https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-images
- https://learn.microsoft.com/legal/marketplace/certification-policies#300-azure-applications
- https://learn.microsoft.com/marketplace/programmatic-deploy-of-marketplace-products

**Holden's decision:** `holden-rhel9-managed-app.md` proposes `rhel-lvm9-gen2` — I concur with the approach but flagged the need to verify exact Gen2 BYOS SKU via CLI.

### 2026-04-01 — Managed App Template Scaffold (mainTemplate + createUiDefinition + viewDefinition)

**Context:** Scaffolded production-quality managed application templates at repo root.

**Files created:**
- `mainTemplate.json` — ARM template deploying RHEL 9 BYOL VM with full networking stack (VNet, subnet, NSG, public IP, NIC) and SSH/password auth switching via `authenticationType` parameter condition
- `createUiDefinition.json` — Portal UI with Basics step (VM name, admin user, CredentialsCombo for SSH/password), VM Settings step (SizeSelector with RHEL BYOS imageReference, VirtualNetworkCombo, NSG name), and BYOL prerequisite InfoBox warning
- `viewDefinition.json` — Overview kind with header/description for post-deployment management page

**Architecture decisions:**
- Used `format()` function for default parameter values (VNet name, NSG name derived from vmName) — keeps parameter contracts clean
- Conditional auth: `osProfile.adminPassword` set only when `authenticationType=password`, `linuxConfiguration` set only when `authenticationType=sshPublicKey`, using ARM `if()` function
- NSG attached at subnet level (not NIC level) — follows Azure networking best practices
- Public IP uses Standard SKU with static allocation — required for production workloads
- SizeSelector includes `imageReference` for RHEL BYOS to show accurate pricing with software costs
- VirtualNetworkCombo supports both new and existing VNets with proper subnet constraints
- Plan block uses hardcoded `redhat:rhel-byos:rhel-lvm9-gen2` values (not parameterized) since this managed app is purpose-built for RHEL 9 BYOS

**Key learnings:**
- `viewDefinition.json` Overview kind only supports `header`, `description`, and `commands` — no dynamic property display from deployment outputs. Deployment outputs are shown automatically in the managed app's Parameters & Outputs blade.
- `createUiDefinition.json` output mappings must exactly match `mainTemplate.json` parameter names
- CredentialsCombo for Linux outputs `authenticationType`, `password`, and `sshPublicKey` — the createUiDefinition `outputs` block must map these to the single `adminPasswordOrKey` parameter using an `if()` expression
- API versions used: Microsoft.Network `2023-11-01`, Microsoft.Compute `2024-07-01`

### 2026-04-01 — Deployment & Packaging Artifacts for Service Catalog

**Context:** Created test/deploy infrastructure for the RHEL 9 PAYGO managed application.

**Files created:**
- `parameters.json` — ARM deployment parameters file with test values (vmName=rhel9-test, sshPublicKey auth, Standard_D2s_v3). Omits params with defaultValue in mainTemplate (location, vnet, subnet, nsg names).
- `deploy.ps1` — Multi-action PowerShell script supporting Validate, Test, Package, and Publish workflows.

**Key patterns:**
- Managed app ZIP must contain `mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json` at the archive root level — no nested folders
- ZIP has a 120 MB limit for service catalog definitions
- `az managedapp definition create` requires `--authorizations` in format `principalId:roleDefinitionId` — script auto-resolves current user + Owner role
- Storage account with public blob access hosts the package URI for the definition
- `--lock-level ReadOnly` prevents modifications to the managed resource group by the consumer
- Validation step (`az deployment group validate`) catches schema/parameter issues before real deployment

**User preferences:**
- jmservera prefers PowerShell for deployment scripts (not Bash)
- Test values: vmName "rhel9-test", adminUsername "azureuser", sshPublicKey auth type
- Location default: westeurope

### 2026-05-15 — GitHub Actions CI/CD for managed app lifecycle

**Context:** Added `.github/workflows/ci.yml` to exercise the managed application end to end in GitHub Actions.

**Architecture and workflow patterns:**
- The CI workflow is intentionally self-contained and does not call `deploy.sh` or `deploy.ps1`; it recreates validation, packaging, publish, deploy, verify, and cleanup with Azure CLI in GitHub Actions.
- Azure authentication for CI should use OIDC with `azure/login@v2` and the three repository/environment secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`.
- ARM-TTK is installed during the run from the official GitHub release, and tests run from a staging folder that includes both `mainTemplate.json` and a compatibility copy named `maintemplate.json`.
- Package validation checks that `app.zip` contains `mainTemplate.json`, `createUiDefinition.json`, and `viewDefinition.json` at the archive root and remains below the 120 MB service catalog limit.
- Integration tests publish the package to a temporary storage account, create a service catalog managed app definition, deploy a managed app instance, and verify the VM plus derived resources (`-vnet`, `-nsg`, `-nic`, `-pip`) in the managed resource group.
- Cleanup uses `if: always()` and captures a managed-resource inventory before deletion so soft-deleted resources can be purged later by resource type; current purge handlers cover Key Vault, App Configuration, and Cognitive Services.

**Key file paths:**
- Workflow: `.github/workflows/ci.yml`
- Team decision note: `.squad/decisions/inbox/naomi-cicd-workflow.md`
- Reusable pattern: `.squad/skills/managed-app-ci-workflow/SKILL.md`
