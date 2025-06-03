#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#
# blockcast.sh
#  A wrapper to install/update/uninstall the Blockcast services via Docker Compose.
#

# -------------- Constants & Defaults --------------
DEFAULT_FUNCTION="install"
COMPOSE_FILE="$HOME/blockcast/docker-compose.yml"
BLOCKCAST_DIR="$HOME/blockcast"
DOCKER_INSTALL_URL="https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh"
IMAGE_VERSION="${IMAGE_VERSION:-stable}"   # Override by exporting before running, if desired.

# -------------- Functions --------------

show_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -in, --install       Install all Blockcast services (default)
  -up, --update        Pull latest images & restart services
  -un, --uninstall     Stop services and optionally remove all data
  -h, --help           Show this help message and exit

Examples:
  $(basename "$0") --install
  $(basename "$0") --update
  $(basename "$0") --uninstall
EOF
  exit 1
}

check_command() {
  # $1 = command to check, $2 = install suggestion
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' is not installed or not in PATH."
    if [ -n "${2:-}" ]; then
      echo "  Install suggestion: $2"
    fi
    exit 1
  fi
}

install_blockcast() {
  echo "→ Installing dependencies…"

  # Ensure wget is present (so we can fetch docker.sh)
  if ! command -v wget &>/dev/null; then
    echo "  'wget' not found. Attempting to install via apt..."
    sudo apt-get update
    sudo apt-get install -y wget
  fi

  echo "→ Installing Docker (via official script)…"
  # This will install Docker if not already present.
  # If already installed, it typically does nothing.
. <(wget -qO- $DOCKER_INSTALL_URL)"


  echo "→ Creating Blockcast directory at '$BLOCKCAST_DIR'…"
  mkdir -p "$BLOCKCAST_DIR"

  read -r -p "Enter port for Watchtower [8080]: " WATCHPORT
  WATCHPORT="${WATCHPORT:-8080}"

  echo "→ Generating docker-compose.yml…"
  tee "$COMPOSE_FILE" > /dev/null <<EOF
x-service: &service
  image: blockcast/cdn_gateway_go:${IMAGE_VERSION}
  restart: unless-stopped
  network_mode: "service:blockcastd"
  volumes:
    - \$HOME/.blockcast/certs:/var/opt/magma/certs
    - \$HOME/.blockcast/snowflake:/etc/snowflake
  labels:
    - "com.centurylinklabs.watchtower.enable=true"

services:
  control_proxy:
    <<: *service
    container_name: control_proxy
    command: /usr/bin/control_proxy

  blockcastd:
    <<: *service
    container_name: blockcastd
    command: /usr/bin/blockcastd -logtostderr=true -v=0
    network_mode: bridge

  beacond:
    <<: *service
    container_name: beacond
    command: /usr/bin/beacond -logtostderr=true -v=0

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    environment:
      - WATCHTOWER_LABEL_ENABLE=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "$WATCHPORT:8080"
EOF

  echo "→ Starting containers…"
  docker compose -f "$COMPOSE_FILE" up -d

  echo ""
  echo "✔ Blockcast installation complete!"
  echo "  Directory: $BLOCKCAST_DIR"
  echo "  Watchtower UI: http://localhost:$WATCHPORT (if running locally)"
}

update_blockcast() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: '$COMPOSE_FILE' not found. Have you run --install first?"
    exit 1
  fi

  echo "→ Stopping existing containers…"
  docker compose -f "$COMPOSE_FILE" down

  echo "→ Pulling latest images…"
  docker compose -f "$COMPOSE_FILE" pull

  echo "→ Re-starting containers…"
  docker compose -f "$COMPOSE_FILE" up -d

  echo ""
  echo "✔ Blockcast services updated!"
}

uninstall_blockcast() {
  if [ ! -d "$BLOCKCAST_DIR" ]; then
    echo "Error: Blockcast directory '$BLOCKCAST_DIR' does not exist."
    exit 1
  fi

  echo "→ Stopping containers (if running)…"
  docker compose -f "$COMPOSE_FILE" down || true

  read -r -p "Wipe all Blockcast data and configuration? [y/N] " RESP
  case "$RESP" in
    [yY][eE][sS]|[yY])
      echo "→ Removing '$BLOCKCAST_DIR'…"
      rm -rf "$BLOCKCAST_DIR"
      echo "✔ All data wiped. Blockcast uninstalled."
      ;;
    *)
      echo "✖ Uninstall canceled. No data was removed."
      ;;
  esac
}

# -------------- Main --------------

# If no arguments, default to “install”
if [ "$#" -eq 0 ]; then
  ACTION="$DEFAULT_FUNCTION"
else
  case "$1" in
    -in|--install)    ACTION="install"    ;;
    -up|--update)     ACTION="update"     ;;
    -un|--uninstall)  ACTION="uninstall"  ;;
    -h|--help)        show_usage         ;;
    *)                echo "Error: Unknown option '$1'"; show_usage ;;
  esac
fi

case "$ACTION" in
  install)   install_blockcast   ;;
  update)    update_blockcast    ;;
  uninstall) uninstall_blockcast ;;
  *)         echo "Error: Unsupported action '$ACTION'"; show_usage ;;
esac

exit 0
