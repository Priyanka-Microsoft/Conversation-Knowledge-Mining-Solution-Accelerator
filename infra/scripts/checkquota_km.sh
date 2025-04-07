#!/bin/bash

# List of Azure regions to check for quota (update as needed)
IFS=', ' read -ra REGIONS <<< "$AZURE_REGIONS"

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
# GPT_MIN_CAPACITY="${GPT_MIN_CAPACITY}"
GPT_MIN_CAPACITY="470"
TEXT_EMBEDDING_MIN_CAPACITY="${TEXT_EMBEDDING_MIN_CAPACITY}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
AZURE_TENANT_ID="${AZURE_TENANT_ID}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"

# Authenticate using Managed Identity
echo "Authentication using Managed Identity..."
if ! az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"; then
   echo "❌ Error: Failed to login using Managed Identity."
   exit 1
fi

echo "🔄 Validating required environment variables..."
if [[ -z "$SUBSCRIPTION_ID" || -z "$GPT_MIN_CAPACITY" || -z "$TEXT_EMBEDDING_MIN_CAPACITY" || -z "$REGIONS" ]]; then
    echo "❌ ERROR: Missing required environment variables."
    exit 1
fi

echo "🔄 Setting Azure subscription..."
if ! az account set --subscription "$SUBSCRIPTION_ID"; then
    echo "❌ ERROR: Invalid subscription ID or insufficient permissions."
    exit 1
fi
echo "✅ Azure subscription set successfully."

# Define models and their minimum required capacities
declare -A MIN_CAPACITY=(
    ["OpenAI.Standard.gpt-4o-mini"]=$GPT_MIN_CAPACITY
    ["OpenAI.GlobalStandard.gpt-4o-mini"]=$GPT_MIN_CAPACITY
    ["OpenAI.Standard.text-embedding-ada-002"]=$TEXT_EMBEDDING_MIN_CAPACITY
)

VALID_REGION=""
for REGION in "${REGIONS[@]}"; do
    echo "----------------------------------------"
    echo "🔍 Checking region: $REGION"

    QUOTA_INFO=$(az cognitiveservices usage list --location "$REGION" --output json)
    if [ -z "$QUOTA_INFO" ]; then
        echo "⚠️ WARNING: Failed to retrieve quota for region $REGION. Skipping."
        continue
    fi

    GPT_MODEL_OK=false
    EMBEDDING_MODEL_OK=false

    for MODEL in "${!MIN_CAPACITY[@]}"; do
        MODEL_INFO=$(echo "$QUOTA_INFO" | awk -v model="\"value\": \"$MODEL\"" '
            BEGIN { RS="},"; FS="," }
            $0 ~ model { print $0 }
        ')

        if [ -z "$MODEL_INFO" ]; then
            echo "⚠️ WARNING: No quota information found for model: $MODEL in $REGION. Skipping."
            continue
        fi

        CURRENT_VALUE=$(echo "$MODEL_INFO" | awk -F': ' '/"currentValue"/ {print $2}' | tr -d ',' | tr -d ' ')
        LIMIT=$(echo "$MODEL_INFO" | awk -F': ' '/"limit"/ {print $2}' | tr -d ',' | tr -d ' ')

        CURRENT_VALUE=${CURRENT_VALUE:-0}
        LIMIT=${LIMIT:-0}

        CURRENT_VALUE=$(echo "$CURRENT_VALUE" | cut -d'.' -f1)
        LIMIT=$(echo "$LIMIT" | cut -d'.' -f1)

        AVAILABLE=$((LIMIT - CURRENT_VALUE))

        echo "✅ Model: $MODEL | Used: $CURRENT_VALUE | Limit: $LIMIT | Available: $AVAILABLE"

        if [ "$AVAILABLE" -ge "${MIN_CAPACITY[$MODEL]}" ]; then
            if [[ "$MODEL" == "OpenAI.Standard.gpt-4o-mini" || "$MODEL" == "OpenAI.GlobalStandard.gpt-4o-mini" ]]; then
                GPT_MODEL_OK=true
            elif [[ "$MODEL" == "OpenAI.Standard.text-embedding-ada-002" ]]; then
                EMBEDDING_MODEL_OK=true
            fi
        fi
    done

    if [[ "$GPT_MODEL_OK" == true && "$EMBEDDING_MODEL_OK" == true ]]; then
        echo "✅ Sufficient quota found in region: $REGION"
        VALID_REGION="$REGION"
        break
    else
        echo "❌ ERROR: Insufficient quota combination in $REGION."
    fi
done

if [ -z "$VALID_REGION" ]; then
    echo "❌ No region with sufficient quota found. Blocking deployment."
    echo "QUOTA_FAILED=true" >> "$GITHUB_ENV"
    exit 0
else
    echo "✅ Final Region: $VALID_REGION"
    echo "VALID_REGION=$VALID_REGION" >> "$GITHUB_ENV"
    exit 0
fi
