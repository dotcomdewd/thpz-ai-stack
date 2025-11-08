##############################################
# Script written by: Goldfynger1337@gmail.com 
#
# The purpose of this script is to install an
# entire AI stack with ease. This was meant 
# to run on Ubuntu Servers. Please use this 
# ethically. This is a powerful stack
#
# TOOLS INSTALLED
#
# - Docker
# - OLLAMA
# - Openweb UI
# - Agent Zero
#
#############################################

#!/usr/bin/env bash
set -euo pipefail

##############################################
# Config (change these if you want)
##############################################
STACK_DIR="/opt/ai-stack"

# Ports on the HOST:
OLLAMA_PORT=11434        # Ollama API
OPENWEBUI_PORT=3000      # Open WebUI
AGENTZERO_PORT=50001     # Agent Zero Web UI

# Default Ollama model to pull
DEFAULT_MODEL="llama3:8b"    # you can change to e.g. mistral:7b

##############################################
# Root check
##############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root:  sudo $0"
  exit 1
fi

echo "=== AI Stack Setup (Ollama + OpenWebUI + Agent Zero) ==="

##############################################
# Detect NVIDIA GPU (hardware presence)
##############################################
HAS_NVIDIA_GPU=0
if lspci | grep -i nvidia > /dev/null 2>&1; then
  HAS_NVIDIA_GPU=1
  echo "🎯 NVIDIA GPU detected on PCI bus."
else
  echo "ℹ️ No NVIDIA GPU detected (or lspci not seeing it). Proceeding without GPU."
fi

##############################################
# Decide if we can run in GPU mode (nvidia-smi)
##############################################
GPU_MODE=0
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi > /dev/null 2>&1; then
  GPU_MODE=1
  echo "✅ GPU mode enabled (nvidia-smi is working)."
else
  echo "ℹ️ nvidia-smi not working; will attempt driver install (once per run) and then proceed in CPU mode."
fi

##############################################
# Try installing NVIDIA driver if GPU present but no nvidia-smi
##############################################
if [[ "$HAS_NVIDIA_GPU" -eq 1 && "$GPU_MODE" -eq 0 ]]; then
  echo "⚠️ NVIDIA GPU found but driver not working/installed."
  echo "   Trying proprietary driver install via ubuntu-drivers (this may have limited effect)."

  apt-get update
  apt-get install -y ubuntu-drivers-common || true
  ubuntu-drivers autoinstall || true

  echo
  echo "ℹ️ Driver install attempt finished."
  echo "   If GPU still isn’t working after a reboot (nvidia-smi fails), the stack will just run in CPU mode."
  echo "   You can fix drivers later (secure boot, specific driver version, etc.) and rerun this script to enable GPU."
fi

##############################################
# Re-check nvidia-smi after potential driver install (same run)
##############################################
if [[ "$GPU_MODE" -eq 0 ]]; then
  if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi > /dev/null 2>&1; then
    GPU_MODE=1
    echo "✅ After driver attempt, nvidia-smi is now working. GPU mode enabled."
  else
    echo "ℹ️ Still no working nvidia-smi; continuing in CPU-only mode for this run."
  fi
fi

##############################################
# Install Docker (if missing)
##############################################
if ! command -v docker &> /dev/null; then
  echo "📦 Installing Docker Engine and Compose plugin..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  systemctl enable --now docker
else
  echo "✅ Docker already installed."
fi

##############################################
# NVIDIA Container Toolkit (if GPU mode)
##############################################
if [[ "$GPU_MODE" -eq 1 ]]; then
  if ! command -v nvidia-ctk > /dev/null 2>&1; then
    echo "📦 Installing NVIDIA Container Toolkit for GPU inside containers..."
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
      gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://#' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    apt-get update
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
  else
    echo "✅ NVIDIA Container Toolkit already installed."
  fi
else
  echo "ℹ️ Skipping NVIDIA Container Toolkit (GPU mode not active)."
fi

##############################################
# Disable host-level Ollama (avoid port conflicts)
##############################################
if systemctl list-unit-files | grep -q "^ollama\.service"; then
  echo "⚠️ Found host ollama.service – disabling to avoid port 11434 conflicts..."
  systemctl stop ollama || true
  systemctl disable ollama || true
fi

##############################################
# Create stack directory
##############################################
mkdir -p "$STACK_DIR"
cd "$STACK_DIR"

##############################################
# Create docker-compose.yml (GPU-aware)
##############################################
echo "📝 Writing docker-compose.yml to ${STACK_DIR} ..."

if [[ "$GPU_MODE" -eq 1 ]]; then
  # GPU-enabled compose
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
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: ["gpu"]

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

else
  # CPU-only compose
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

fi

echo "✅ docker-compose.yml created."

##############################################
# Bring up the stack
##############################################
echo "🚀 Starting Docker stack (Ollama + OpenWebUI + Agent Zero)..."
docker compose up -d

##############################################
# Pull default Ollama model
##############################################
echo "📥 Pulling default Ollama model: ${DEFAULT_MODEL}"
if docker exec -it ollama ollama pull "${DEFAULT_MODEL}"; then
  echo "✅ Model ${DEFAULT_MODEL} pulled successfully."
else
  echo "⚠️ Failed to pull model ${DEFAULT_MODEL}."
  echo "   You can try manually with:"
  echo "   sudo docker exec -it ollama ollama pull ${DEFAULT_MODEL}"
fi

##############################################
# Create a systemd service for auto-start
##############################################
SERVICE_FILE="/etc/systemd/system/ai-stack.service"

cat > "$SERVICE_FILE" <<EOS
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
HOST_IP=$(hostname -I | awk '{print $1}')

echo
echo "=========================================================="
echo "✅ AI stack is up and running."
echo
echo "  Ollama API:      http://${HOST_IP}:${OLLAMA_PORT}"
echo "  Open WebUI:      http://${HOST_IP}:${OPENWEBUI_PORT}"
echo "  Agent Zero UI:   http://${HOST_IP}:${AGENTZERO_PORT}"
echo
if [[ "$GPU_MODE" -eq 1 ]]; then
  echo "  Mode:            GPU (NVIDIA)"
else
  echo "  Mode:            CPU-only"
fi
echo
echo "On reboot, the stack will auto-start via ai-stack.service."
echo "To manage manually:"
echo "  cd ${STACK_DIR}"
echo "  sudo docker compose ps"
echo "  sudo systemctl restart ai-stack"
echo "=========================================================="
