# Squad Decisions

## Active Decisions

### 1. Switch from BYOS to PAYGO for RHEL 9 Managed App

**Date:** 2026-04-01T2130  
**Decision Type:** Image licensing model change  
**Status:** Implemented by coordinator (direct-mode edit)  
**Impact:** All three managed app template files

The managed application templates switched from RHEL 9 BYOL (Bring Your Own License) to PAYGO (Pay-As-You-Go) licensing. This simplifies deployment by eliminating marketplace plan blocks, subscription requirements, and enrollment steps. Users now benefit from pre-entitled VMs with RHUI, lower operational friction, and per-minute Azure pricing.

Changes applied to:
- mainTemplate.json — Image reference updated: `redhat:rhel-byos:rhel-lvm9-gen2` → `RedHat:RHEL:9-lvm-gen2:latest`
- createUiDefinition.json — Removed BYOL warning; updated descriptions
- viewDefinition.json — Post-deployment customization aligned with PAYGO

---

### 2. Managed App Template Scaffold

**Author:** Naomi (Bicep Engineer)  
**Date:** 2026-04-01  
**Status:** Implemented

Scaffolded three production-quality managed application templates:
- **mainTemplate.json** — ARM template deploying RHEL 9 VM with full networking stack
- **createUiDefinition.json** — Azure portal UI definition with two-step wizard
- **viewDefinition.json** — Post-deployment overview customization

Key design decisions:
- Conditional authentication (SSH key or password via ARM `if()`)
- NSG at subnet level (Azure networking best practice)
- Standard SKU public IP with static allocation
- Production-ready for packaging into managed app definition

---

### 3. Deployment & Packaging Artifacts

**Author:** Naomi (Bicep Engineer)  
**Date:** 2026-04-01  
**Status:** Implemented

Created two artifacts for validation and packaging workflows:

**parameters.json** — ARM parameters file
- Minimal parameter set (required values only)
- SSH key placeholder for testing
- Relies on mainTemplate.json defaultValues for networking names
- Must be updated before validation

**deploy.ps1** — PowerShell orchestration script
- Action modes: Validate, Test, Package, Publish, All
- Uses `az cli` for cross-platform CI/CD compatibility
- Auto-resolves current user + Owner role for authorizations
- Requires explicit storage account name for Publish (safety measure)

Rationale: Parameters file minimalism prevents drift; script uses az cli for consistency and portability.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
