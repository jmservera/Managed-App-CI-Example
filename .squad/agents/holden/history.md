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
- **Naomi's marketplace-vm-plan pattern** implements Holden's plan block requirements and validates the exact SKU discovery workflow
- Both agents converged on `rhel-lvm9-gen2` as the correct SKU for Gen2 RHEL 9 BYOS deployments
- Naomi's reusable skill (`.squad/skills/marketplace-vm-plan/SKILL.md`) operationalizes Holden's architectural findings
- Decisions merged into unified `decisions.md` to cross-reference both contributions

### 2026-05-15 — Managed Application CI/CD & Documentation Delivery

**Participants:** Holden (README documentation), Naomi (CI/CD workflow), Scribe (Orchestration)

**Cross-Agent Notes:**
- **Holden's README** documents CI/CD workflow expectations before Naomi's implementation (`.github/workflows/ci.yml`)
- **Naomi's CI workflow** fully aligns with Holden's documented architecture: OIDC authentication, ARM-TTK validation, managed app deployment verification, soft-delete cleanup
- Both agents' decisions merged into unified decisions log; orchestration logs created for accountability
- Session log documents concurrent delivery coordination and cross-agent alignment

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-15 — README for managed app operations

**Context:** Added root `README.md` to explain direct ARM deployment, managed app packaging, Service Catalog publishing, UI sandbox testing, and planned CI usage.

**Lasting notes:**
- Primary operator entry points are `README.md`, `deploy.sh`, `deploy.ps1`, `mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json`, and `parameters.json`.
- The documentation standard for this repo should stay practical: copy-paste Azure CLI commands, Portal navigation steps, and explicit differences between direct ARM deployment and Service Catalog deployment.
- The managed app package is always the root-level ZIP of `mainTemplate.json`, `createUiDefinition.json`, and `viewDefinition.json`; direct testing continues to use `parameters.json`.
- CI documentation is anchored to the expected workflow path `.github/workflows/ci.yml`, with OIDC-based GitHub Actions authentication and ARM-TTK plus deployment verification as the intended control gates.

### 2026-04-01 — RHEL 9 BYOL Managed Application Research

**Context:** Partner needs a managed application template deploying RHEL 9 BYOL (BYOS) VM from Azure Marketplace.

**RHEL 9 BYOS Marketplace Image Reference:**
- **Publisher:** `redhat` (always lowercase)
- **Offer:** `rhel-byos`
- **SKU:** `rhel-lvm9-gen2` (Gen2 LVM-partitioned; for Gen1 use `rhel-lvm9`)
- **Version:** `latest` (auto-selects latest RHEL 9.x minor version)
- **Full URN:** `redhat:rhel-byos:rhel-lvm9-gen2:latest`
- BYOS images are "Gold Images" requiring Red Hat Cloud Access enrollment and subscription enablement.
- Marketplace terms must be accepted once per subscription per SKU: `az vm image terms accept --publisher redhat --offer rhel-byos --plan rhel-lvm9-gen2`

**Managed Application Template Structure:**
- `mainTemplate.json` — ARM template defining deployed resources (Bicep must be compiled to ARM JSON)
- `createUiDefinition.json` — Portal UI definition for deployment wizard
- `viewDefinition.json` — (optional) Custom views for managing the app post-deployment
- All files at root of a `.zip` package (max 120 MB for service catalog)
- For marketplace: `_artifactsLocation` and `_artifactsLocationSasToken` params required

**Marketplace Image Plan Block (ARM/Bicep):**
- VM resources using marketplace images require BOTH `plan` and `imageReference`
- In ARM JSON the `plan` block is a sibling to `properties` on the VM resource
- `plan.name` = SKU value, `plan.product` = offer, `plan.publisher` = publisher
- `imageReference` goes inside `properties.storageProfile` with publisher/offer/sku/version
- Certification policy 300.4.8: imageReference must include plan object for marketplace images

**PAYGO vs BYOS Decision (2026-04-01T2130):**
Coordinator pivoted to PAYGO model after initial BYOS research. Published templates now use `RedHat:RHEL:9-lvm-gen2:latest` (capitalized publisher, no plan block). This trade-off favors deployment velocity and removes licensing/enrollment complexity at the cost of per-minute billing.
