# Managed App CI Workflow

## When to use
Use this pattern when a repository packages Azure Managed Application artifacts (`mainTemplate.json`, `createUiDefinition.json`, `viewDefinition.json`) and needs CI to validate both the package and the live service catalog deployment flow.

## Pattern
1. Authenticate with GitHub Actions OIDC via `azure/login@v2`.
2. Generate ephemeral deployment inputs in the workspace, including an SSH public key for test parameters.
3. Install ARM-TTK from the latest GitHub release inside the workflow.
4. Run ARM-TTK in a staging folder that preserves the managed app filenames but also includes a `maintemplate.json` copy for compatibility with `Test-AzTemplate`.
5. Run `az deployment group validate` with generated parameters.
6. Build `app.zip` with the required files at archive root and enforce the 120 MB service catalog limit.
7. Upload `app.zip` as a workflow artifact.
8. Create a temporary storage account, upload the package, publish a managed app definition, and deploy a `ServiceCatalog` managed app instance.
9. Verify the managed resource group contains the expected resources derived from the VM name.
10. In an `if: always()` cleanup step, delete the managed app instance, delete the definition, delete both resource groups, and purge supported soft-deleted resources based on a captured resource inventory.

## Notes
- For service principals signed in with OIDC, resolve the authorization principal with `az ad sp show --id $AZURE_CLIENT_ID --query id -o tsv`.
- The built-in Owner role definition ID is `8e3af657-a8ff-443c-a75c-2fe8c4bcb635`.
- A resource-inventory-driven purge pass keeps cleanup extensible as managed templates add Key Vault, App Configuration, Cognitive Services, or other soft-delete-capable services.
