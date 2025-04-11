#!/bin/bash

set -e  # Exit on first error
set -o pipefail
set -u  # Treat unset variables as error

# === Configuration Parameters ===
STORAGE_ACCOUNT_NAME="$1"
CONTAINER_NAME="$2"
BASE_URL="$3"
MANAGED_IDENTITY_CLIENT_ID="$4"
KEY_VAULT_NAME="$5"
SQL_SERVER_NAME="$6"
SQL_DB_NAME="$7"

# === Functions ===
log() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

trap 'error "An unexpected error occurred. Please check the logs."' ERR

# === Step 1: Copy KB files ===
log "Copying knowledge base files..."
curl -s -o copy_kb_files.sh "${BASE_URL}infra/scripts/copy_kb_files.sh"
chmod +x copy_kb_files.sh
./copy_kb_files.sh "$STORAGE_ACCOUNT_NAME" "$CONTAINER_NAME" "$BASE_URL" "$MANAGED_IDENTITY_CLIENT_ID"

# === Step 2: Run create index scripts ===
log "Creating indexes..."
curl -s -o run_create_index_scripts.sh "${BASE_URL}infra/scripts/run_create_index_scripts.sh"
chmod +x run_create_index_scripts.sh
./run_create_index_scripts.sh "$BASE_URL" "$KEY_VAULT_NAME" "$MANAGED_IDENTITY_CLIENT_ID"

# === Step 3: SQL User & Role Setup ===
log "Setting up SQL users and roles..."
curl -s -o create-sql-user-and-role.ps1 "${BASE_URL}infra/scripts/add_user_scripts/create-sql-user-and-role.ps1"
chmod +x create-sql-user-and-role.ps1

# Note: You'll need to pass user info (client ID, display name, role) via environment vars or args.
# Here is a sample with hardcoded values for demo:

pwsh -File ./create-sql-user-and-role.ps1 \
    -SqlServerName "$SQL_SERVER_NAME" \
    -SqlDatabaseName "$SQL_DB_NAME" \
    -ClientId "<client-id-1>" \
    -DisplayName "<user-1>" \
    -ManagedIdentityClientId "$MANAGED_IDENTITY_CLIENT_ID" \
    -DatabaseRole "<role-1>"

log "Sample data processing completed successfully!"
