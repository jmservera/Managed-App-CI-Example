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

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

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
