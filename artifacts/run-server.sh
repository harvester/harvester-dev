#!/bin/bash -eu
# Run nginx server to serve artifacts with bind mounts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"

PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")


CONTAINER_NAME="${PREFIX}-artifacts-server"
IMAGE_NAME="${PREFIX}-artifacts-server"
PORT="${PORT:-8787}"

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Stopping and removing existing container..."
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi


#opt-in to BuildKit for better performance and caching
export DOCKER_BUILDKIT=1

# Build the image
echo "Building Docker image..."
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"

# in case empty
mkdir -p "$SCRIPT_DIR/images"
mkdir -p "$SCRIPT_DIR/isos"

# Run the container with bind mounts
echo "Starting artifacts server on port $PORT..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$PORT:80" \
  -v "$SCRIPT_DIR/images:/usr/share/nginx/html/images:ro" \
  -v "$SCRIPT_DIR/isos:/usr/share/nginx/html/isos:ro" \
  --restart unless-stopped \
  "$IMAGE_NAME"

echo "Artifacts server is running at http://localhost:$PORT"
echo ""
echo "To stop the server, run:"
echo "  docker stop $CONTAINER_NAME"
echo ""
echo "To view logs, run:"
echo "  docker logs -f $CONTAINER_NAME"
