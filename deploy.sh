#!/usr/bin/env bash
# deploy.sh
#
# SYNOPSIS
#   Validates, tests, packages, and publishes the RHEL 9 PAYGO managed application
#   to an Azure Service Catalog.
#
# DESCRIPTION
#   Provides four operations:
#     validate  - Runs az deployment group validate against mainTemplate.json
#     test      - Deploys mainTemplate.json directly to a resource group using parameters.json
#     package   - Creates app.zip from the three managed app JSON files
#     publish   - Uploads app.zip to a storage account and creates the managed app definition
#
# USAGE
#   ./deploy.sh [options] -g <ResourceGroupName>
#
# OPTIONS
#   -g  Resource group name (required)
#   -l  Azure region (default: westeurope)
#   -s  Storage account name (required for publish)
#   -c  Blob container name (default: appcontainer)
#   -n  App definition name (default: rhel9-managed-app)
#   -d  App definition display name (default: RHEL 9 PAYGO VM)
#   -e  App definition description
#   -k  Lock level: ReadOnly or CanNotDelete (default: ReadOnly)
#   -a  Action: validate, test, package, publish, all (default: all)
#   -h  Show this help
#
# EXAMPLES
#   ./deploy.sh -a validate -g myRG
#   ./deploy.sh -a test -g myRG
#   ./deploy.sh -a publish -g myRG -s mystgacct123

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/mainTemplate.json"
UI_DEF_FILE="$SCRIPT_DIR/createUiDefinition.json"
VIEW_DEF_FILE="$SCRIPT_DIR/viewDefinition.json"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.json"
ZIP_FILE="$SCRIPT_DIR/app.zip"

# ─────────────────────────────────────────────
# Defaults
# ─────────────────────────────────────────────
RESOURCE_GROUP_NAME=""
LOCATION="westeurope"
STORAGE_ACCOUNT_NAME=""
STORAGE_CONTAINER_NAME="appcontainer"
APP_DEFINITION_NAME="rhel9-managed-app"
APP_DEFINITION_DISPLAY_NAME="RHEL 9 PAYGO VM"
APP_DEFINITION_DESCRIPTION="Deploys a Red Hat Enterprise Linux 9 pay-as-you-go virtual machine with networking stack."
LOCK_LEVEL="ReadOnly"
ACTION="all"

# ─────────────────────────────────────────────
# Helper: coloured output
# ─────────────────────────────────────────────
write_step() { printf "\n\033[0;36m▶ %s\033[0m\n" "$1"; }
write_ok()   { printf "  \033[0;32m✔ %s\033[0m\n" "$1"; }
write_fail() { printf "  \033[0;31m✘ %s\033[0m\n" "$1" >&2; }
write_warn() { printf "  \033[0;33m⚠ %s\033[0m\n" "$1"; }
write_info() { printf "  %s\n" "$1"; }

# ─────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────
usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
}

# ─────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────
while getopts ":g:l:s:c:n:d:e:k:a:h" opt; do
    case $opt in
        g) RESOURCE_GROUP_NAME="$OPTARG" ;;
        l) LOCATION="$OPTARG" ;;
        s) STORAGE_ACCOUNT_NAME="$OPTARG" ;;
        c) STORAGE_CONTAINER_NAME="$OPTARG" ;;
        n) APP_DEFINITION_NAME="$OPTARG" ;;
        d) APP_DEFINITION_DISPLAY_NAME="$OPTARG" ;;
        e) APP_DEFINITION_DESCRIPTION="$OPTARG" ;;
        k) LOCK_LEVEL="$OPTARG" ;;
        a) ACTION="${OPTARG,,}" ;;  # lowercase
        h) usage ;;
        :) write_fail "Option -$OPTARG requires an argument."; exit 1 ;;
        \?) write_fail "Unknown option: -$OPTARG"; exit 1 ;;
    esac
done

if [[ -z "$RESOURCE_GROUP_NAME" ]]; then
    write_fail "Resource group name is required. Use -g <name>."
    exit 1
fi

case "$LOCK_LEVEL" in
    ReadOnly|CanNotDelete) ;;
    *) write_fail "Lock level must be ReadOnly or CanNotDelete."; exit 1 ;;
esac

case "$ACTION" in
    validate|test|package|publish|all) ;;
    *) write_fail "Action must be validate, test, package, publish, or all."; exit 1 ;;
esac

# ─────────────────────────────────────────────
# Step 1: Validate the ARM template
# ─────────────────────────────────────────────
invoke_validate() {
    write_step "Validating ARM template against resource group '$RESOURCE_GROUP_NAME'..."

    local rg_exists
    rg_exists=$(az group exists --name "$RESOURCE_GROUP_NAME" 2>/dev/null)
    if [[ "$rg_exists" != "true" ]]; then
        write_info "Resource group '$RESOURCE_GROUP_NAME' not found — creating in '$LOCATION'..."
        az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
        write_ok "Resource group created."
    fi

    az deployment group validate \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --output table

    write_ok "Template validation succeeded."
}

# ─────────────────────────────────────────────
# Step 2: Test deploy (deploys real resources)
# ─────────────────────────────────────────────
invoke_test_deploy() {
    write_step "Test-deploying mainTemplate.json to resource group '$RESOURCE_GROUP_NAME'..."
    write_warn "This creates real Azure resources. Press Ctrl+C to abort."

    local rg_exists
    rg_exists=$(az group exists --name "$RESOURCE_GROUP_NAME" 2>/dev/null)
    if [[ "$rg_exists" != "true" ]]; then
        az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
    fi

    local deployment_name="test-deploy-$(date -u '+%Y%m%d-%H%M%S')"

    az deployment group create \
        --name "$deployment_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --output table

    write_ok "Test deployment succeeded: $deployment_name"
}

# ─────────────────────────────────────────────
# Step 3: Package the managed app ZIP
# ─────────────────────────────────────────────
invoke_package() {
    write_step "Packaging managed application files into app.zip..."

    for f in "$TEMPLATE_FILE" "$UI_DEF_FILE" "$VIEW_DEF_FILE"; do
        if [[ ! -f "$f" ]]; then
            write_fail "Required file not found: $f"
            exit 1
        fi
    done

    # Remove existing zip to avoid stale content
    [[ -f "$ZIP_FILE" ]] && rm -f "$ZIP_FILE"

    # Create ZIP — files must be at the root level of the archive
    (cd "$SCRIPT_DIR" && zip -q "$ZIP_FILE" \
        "$(basename "$TEMPLATE_FILE")" \
        "$(basename "$UI_DEF_FILE")" \
        "$(basename "$VIEW_DEF_FILE")")

    local zip_bytes zip_size_mb
    zip_bytes=$(wc -c < "$ZIP_FILE")
    zip_size_mb=$(awk "BEGIN {printf \"%.2f\", $zip_bytes/1048576}")
    write_ok "Created app.zip ($zip_size_mb MB)"

    # Managed app ZIP has a 120 MB limit
    if awk "BEGIN {exit !($zip_size_mb > 120)}"; then
        write_fail "app.zip exceeds the 120 MB limit for service catalog managed applications."
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Step 4: Publish managed app definition
# ─────────────────────────────────────────────
invoke_publish() {
    write_step "Publishing managed application definition to service catalog..."

    if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
        write_fail "Storage account name is required for publishing. Use -s <name>."
        exit 1
    fi

    # Ensure the ZIP exists
    if [[ ! -f "$ZIP_FILE" ]]; then
        write_info "app.zip not found — packaging first..."
        invoke_package
    fi

    # Ensure resource group
    local rg_exists
    rg_exists=$(az group exists --name "$RESOURCE_GROUP_NAME" 2>/dev/null)
    if [[ "$rg_exists" != "true" ]]; then
        az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
        write_ok "Resource group '$RESOURCE_GROUP_NAME' created."
    fi

    # Create storage account if it doesn't exist
    write_info "Ensuring storage account '$STORAGE_ACCOUNT_NAME'..."
    local stg_available
    stg_available=$(az storage account check-name --name "$STORAGE_ACCOUNT_NAME" --query "nameAvailable" --output tsv 2>/dev/null)
    if [[ "$stg_available" == "true" ]]; then
        write_info "Creating storage account '$STORAGE_ACCOUNT_NAME'..."
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --output none
        write_ok "Storage account created."
    else
        write_ok "Storage account '$STORAGE_ACCOUNT_NAME' already exists."
    fi

    # Create blob container (idempotent)
    write_info "Ensuring blob container '$STORAGE_CONTAINER_NAME'..."
    az storage container create \
        --name "$STORAGE_CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --auth-mode login \
        --public-access blob \
        --output none 2>/dev/null || true

    # Upload app.zip to blob storage
    write_info "Uploading app.zip..."
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$STORAGE_CONTAINER_NAME" \
        --auth-mode login \
        --name app.zip \
        --file "$ZIP_FILE" \
        --overwrite \
        --output none

    write_ok "app.zip uploaded to storage."

    # Get the blob URL for the managed app definition
    local blob_uri
    blob_uri=$(az storage blob url \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$STORAGE_CONTAINER_NAME" \
        --auth-mode login \
        --name app.zip \
        --output tsv)

    write_info "Package URI: $blob_uri"

    # Get current user's object ID and Owner role definition for --authorizations
    write_info "Resolving current user principal and Owner role..."
    local user_id role_id
    user_id=$(az ad signed-in-user show --query "id" --output tsv)
    role_id=$(az role definition list --name "Owner" --query "[0].name" --output tsv)

    if [[ -z "$user_id" || -z "$role_id" ]]; then
        write_fail "Could not resolve user ID or Owner role ID. Ensure you are signed in with 'az login'."
        exit 1
    fi

    local authorization="${user_id}:${role_id}"
    write_info "Authorization: $authorization"

    # Create the managed application definition
    write_info "Creating managed app definition '$APP_DEFINITION_NAME'..."
    az managedapp definition create \
        --name "$APP_DEFINITION_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --lock-level "$LOCK_LEVEL" \
        --display-name "$APP_DEFINITION_DISPLAY_NAME" \
        --description "$APP_DEFINITION_DESCRIPTION" \
        --authorizations "$authorization" \
        --package-file-uri "$blob_uri" \
        --output table

    write_ok "Managed application definition '$APP_DEFINITION_NAME' published to service catalog."
    printf "\n\033[0;36m  You can now deploy it from the Azure Portal:\033[0m\n"
    printf "    Portal → Create a resource → Service Catalog Managed Application → '%s'\n" "$APP_DEFINITION_DISPLAY_NAME"
}

# ─────────────────────────────────────────────
# Main — dispatch based on -a action
# ─────────────────────────────────────────────
case "$ACTION" in
    validate)
        invoke_validate
        ;;
    test)
        invoke_validate
        invoke_test_deploy
        ;;
    package)
        invoke_package
        ;;
    publish)
        invoke_validate
        invoke_package
        invoke_publish
        ;;
    all)
        invoke_validate
        invoke_package
        invoke_publish
        ;;
esac

printf "\n\033[0;32m✅ Done.\033[0m\n"
