#!/usr/bin/env bash
set -euo pipefail

##############################################
# Config
##############################################
STACK_DIR="/opt/ai-stack"

# Host ports
OLLAMA_PORT=11434
OPENWEBUI_PORT=3000
AGENTZERO_PORT=50001

##############################################
# Root check
##############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root:  sudo $0"
  exit 1
fi

echo "=== AI Stack Setup on Kali (Ollama + OpenWebUI + Agent Zero, CPU-only) ==="

##############################################
# Basic dependencies
##############################################
echo "📦 Installing base packages..."
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

##############################################
# Install Docker if missing
##############################################
if ! command -v docker &>/dev/null; then
  echo "📦 Docker not found, installing via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
else
  echo "✅ Docker already installed."
fi

# Install docker compose plugin (V2)
if ! docker compose version &>/dev/null; then
  echo "📦 Installing docker-compose-plugin..."
  apt-get install -y docker-compose-plugin
else
  echo "✅ docker compose plugin already installed."
fi

systemctl enable --now docker

##############################################
# Create stack directory
##############################################
mkdir -p "$STACK_DIR"
cd "$STACK_DIR"

##############################################
# Write docker-compose.yml (CPU-only)
##############################################
cat > docker-compose.yml <<EOF
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - ENABLE_NETWORK_ACCESS=false
    depends_on:
      - ollama
    ports:
      - "${OPENWEBUI_PORT}:8080"
    volumes:
      - openwebui_data:/app/backend/data

  agentzero:
    image: agent0ai/agent-zero:latest
    container_name: agentzero
    restart: unless-stopped
    ports:
      - "${AGENTZERO_PORT}:80"
    volumes:
      - agentzero_data:/a0

volumes:
  ollama_data:
  openwebui_data:
  agentzero_data:
EOF

echo "✅ docker-compose.yml written to ${STACK_DIR}"

##############################################
# Bring up the stack
##############################################
echo "🚀 Starting Docker stack (this will pull images on first run)..."
docker compose up -d

##############################################
# Create systemd service for auto-start
##############################################
SERVICE_FILE="/etc/systemd/system/ai-stack.service"

cat > "\$SERVICE_FILE" <<EOS
[Unit]
Description=AI Stack (Ollama + Open WebUI + Agent Zero)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=${STACK_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOS

systemctl daemon-reload
systemctl enable ai-stack.service

echo "✅ systemd service ai-stack.service installed and enabled."

##############################################
# Done
##############################################
HOST_IP=\$(hostname -I | awk '{print \$1}')

echo
echo "=========================================================="
echo "✅ AI stack is up and running (CPU-only)."
echo
echo "  Ollama API:      http://${HOST_IP}:${OLLAMA_PORT}"
echo "  Open WebUI:      http://${HOST_IP}:${OPENWEBUI_PORT}"
echo "  Agent Zero UI:   http://${HOST_IP}:${AGENTZERO_PORT}"
echo
echo "On reboot, the stack auto-starts via: ai-stack.service"
echo "To manage manually:"
echo "  cd ${STACK_DIR}"
echo "  sudo docker compose ps"
echo "  sudo systemctl restart ai-stack"
echo "=========================================================="
