#!/bin/bash
#
### Quick script to reboot the THPZ AI Stack

##############################################
# Root check
##############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root:  sudo $0"
  exit 1
fi

echo "=== AI Stack Restart (Ollama + OpenWebUI + Agent Zero) ==="

cd /opt/ai-stack
echo "Stopping Docker- "
sudo docker compose down
echo "Starting Docker- "
sudo docker compose up -d

echo 
echo "=== Done restaerting AI Stack ==="
echo
