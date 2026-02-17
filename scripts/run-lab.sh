#!/bin/bash
# scripts/run-lab.sh — Launch the jupyterlab-ai-aider container with AWS credentials.
#
# Reads long-lived credentials from the 'aiderz' profile in ~/.aws/credentials,
# mints temporary STS session credentials, and passes them into the container.
#
# Usage:
#   ./scripts/run-lab.sh                          # start JupyterLab on port $UID
#   ./scripts/run-lab.sh --port 9999              # custom port
#   AIDERZ_AWS_PROFILE=myprofile ./scripts/run-lab.sh  # custom AWS profile

set -euo pipefail

IMAGE=${IMAGE:-ssadedin/jupyterlab-ai-aider}
PROFILE="${AIDERZ_AWS_PROFILE:-aiderz}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

# ── Parse arguments ──────────────────────────────────────────────────────
PORT="${PORT:-$(id -u)}"
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ── Read AWS credentials from profile ────────────────────────────────────
CREDS_FILE="$HOME/.aws/credentials"

if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: $CREDS_FILE not found" >&2
    exit 1
fi

AWS_ACCESS_KEY_ID=$(awk -v p="[$PROFILE]" '
    $0==p {f=1; next}
    /^\[/ {f=0}
    f && $1=="aws_access_key_id" {print $3; exit}
' "$CREDS_FILE")

AWS_SECRET_ACCESS_KEY=$(awk -v p="[$PROFILE]" '
    $0==p {f=1; next}
    /^\[/ {f=0}
    f && $1=="aws_secret_access_key" {print $3; exit}
' "$CREDS_FILE")

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: Could not find credentials for profile '$PROFILE' in $CREDS_FILE" >&2
    echo >&2
    echo "Please add a [$PROFILE] section to $CREDS_FILE with:" >&2
    echo "  aws_access_key_id = ..." >&2
    echo "  aws_secret_access_key = ..." >&2
    exit 1
fi

# ── Mint temporary STS session credentials (8 hours) ─────────────────────
echo "Minting temporary AWS credentials from profile '$PROFILE'..."

STS_JSON=$(AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    aws sts get-session-token --duration-seconds 28800 --output json)

TEMP_KEY=$(echo "$STS_JSON" | jq -r .Credentials.AccessKeyId)
TEMP_SECRET=$(echo "$STS_JSON" | jq -r .Credentials.SecretAccessKey)
TEMP_TOKEN=$(echo "$STS_JSON" | jq -r .Credentials.SessionToken)
EXPIRATION=$(echo "$STS_JSON" | jq -r .Credentials.Expiration)

if [ -z "$TEMP_KEY" ] || [ "$TEMP_KEY" = "null" ]; then
    echo "Error: Failed to obtain temporary AWS credentials. Check errors above." >&2
    exit 1
fi

echo "Temporary credentials obtained (expire at $EXPIRATION)"

# ── Launch container ─────────────────────────────────────────────────────
echo
echo "============================================"
echo "  JupyterLab: http://127.0.0.1:$PORT/lab"
echo "============================================"
echo
echo "(Ignore the port 8888 URL printed by JupyterLab below — use the URL above)"
echo
exec docker run \
    -e AWS_ACCESS_KEY_ID="$TEMP_KEY" \
    -e AWS_SECRET_ACCESS_KEY="$TEMP_SECRET" \
    -e AWS_SESSION_TOKEN="$TEMP_TOKEN" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    -v "$(pwd):$(pwd)" \
    -w "$(pwd)" \
    --rm -it \
    -p "$PORT:8888" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" \
    "$IMAGE"
