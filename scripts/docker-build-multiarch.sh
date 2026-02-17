#!/usr/bin/env bash
# scripts/docker-build-multiarch.sh — Build multi-architecture Docker images.
#
# Builds the jupyterlab-ai-aider image for linux/amd64 and linux/arm64.
# Requires the jupyterlab-ai-groovy image to be available (locally or in registry).
#
# Usage:
#   ./scripts/docker-build-multiarch.sh                     # build & load for current arch
#   ./scripts/docker-build-multiarch.sh --push              # build both archs & push to registry
#   ./scripts/docker-build-multiarch.sh --push --no-cache   # rebuild without cache
#   ./scripts/docker-build-multiarch.sh --platform linux/amd64  # build specific arch
#
# Environment variables:
#   IMAGE_NAME    — image name (default: jupyterlab-ai-aider)
#   REGISTRY      — registry prefix, e.g. ghcr.io/myorg (default: none, local only)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-jupyterlab-ai-aider}"
REGISTRY="${REGISTRY:-ssadedin}"
BUILDER_NAME="multiarch"
PLATFORMS="linux/amd64,linux/arm64"

# Parse flags
PUSH=false
NO_CACHE=false
CUSTOM_PLATFORM=""
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --platform)
            CUSTOM_PLATFORM="$2"
            shift 2
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

# Prepend registry if set
FULL_IMAGE="${IMAGE_NAME}"
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"
fi

# Ensure buildx builder exists
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "==> Creating buildx builder '$BUILDER_NAME'..."
    docker buildx create --name "$BUILDER_NAME" --driver docker-container --bootstrap
fi
docker buildx use "$BUILDER_NAME"

# Build args
BUILD_ARGS=(
    -f "$REPO_ROOT/Dockerfile"
    -t "$FULL_IMAGE"
    --build-arg "REGISTRY=$REGISTRY"
)

if $NO_CACHE; then
    BUILD_ARGS+=(--no-cache)
fi

if $PUSH; then
    # Multi-platform: build for both architectures and push
    PLATFORMS="${CUSTOM_PLATFORM:-$PLATFORMS}"
    BUILD_ARGS+=(--platform "$PLATFORMS" --push)
    echo "==> Building '$FULL_IMAGE' for $PLATFORMS and pushing..."
else
    # Local: build for the specified (or current) platform and load into Docker
    if [ -n "$CUSTOM_PLATFORM" ]; then
        BUILD_ARGS+=(--platform "$CUSTOM_PLATFORM")
    fi
    BUILD_ARGS+=(--load)
    echo "==> Building '$FULL_IMAGE' for ${CUSTOM_PLATFORM:-current platform} (local)..."
fi

docker buildx build "${BUILD_ARGS[@]}" "$REPO_ROOT"

echo "==> Done."
if $PUSH; then
    echo "==> Pushed '$FULL_IMAGE' with platforms: $PLATFORMS"
else
    echo "==> Loaded '$FULL_IMAGE' into local Docker."
fi
