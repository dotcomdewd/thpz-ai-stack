#!/usr/bin/env bash
set -euo pipefail

########################################
# This script will check your AI stack
# for any errors and ensure proper setup
########################################

########################################
# CONFIG – EDIT THESE FOR YOUR SETUP  #
########################################

# You can override any of these via environment variables when running the script.
# Example:
#   OLLAMA_URL="http://ollama:11434" ./check_stack.sh

: "${OLLAMA_URL:=http://ollama:11434}"
: "${AGENT_ZERO_URL:=http://ollama:50001}"
: "${OPENWEBUI_URL:=http://openwebui:3000}"

# Model name as configured in Agent Zero (whatever you normally call from it)
: "${AGENT_ZERO_MODEL:=llama3:b}"


########################################
# Helpers                              #
########################################

ok()   { printf "\033[32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[FAIL]\033[0m %s\n" "$*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 1
  fi
}

########################################
# Check Ollama                         #
########################################

check_ollama() {
  echo "==> Checking Ollama at: $OLLAMA_URL"

  # Basic connectivity + HTTP code
  local http_code
  http_code=$(curl -s -o /tmp/ollama_tags.json -w "%{http_code}" \
    "$OLLAMA_URL/api/tags" || true)

  if [ "$http_code" != "200" ]; then
    err "Ollama /api/tags returned HTTP $http_code"
    echo "     URL: $OLLAMA_URL/api/tags"
    return 1
  fi

  # Optional: sanity-check response
  if grep -q '"models"' /tmp/ollama_tags.json; then
    ok "Ollama is reachable and returned a models list."
  else
    warn "Ollama responded but /api/tags output didn't look like a models list."
    warn "Check /tmp/ollama_tags.json if you want to inspect it."
  fi
}

########################################
# Check Agent Zero -> Ollama           #
########################################

check_agent_zero() {
  echo "==> Checking Agent Zero at: $AGENT_ZERO_URL"

  # Try a simple OpenAI-style /v1/chat/completions call.
  # Adjust path or payload if your Agent Zero config uses something else.
  local http_code
  http_code=$(curl -s -o /tmp/agent_zero_resp.json -w "%{http_code}" \
    -X POST "$AGENT_ZERO_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "$AGENT_ZERO_MODEL",
  "messages": [
    { "role": "user", "content": "Say 'pong'." }
  ],
  "max_tokens": 10,
  "stream": false
}
EOF
  )

  if [ "$http_code" != "200" ]; then
    err "Agent Zero /v1/chat/completions returned HTTP $http_code"
    echo "     This often means Agent Zero can't reach Ollama, or the model name is wrong."
    echo "     Check /tmp/agent_zero_resp.json for details."
    return 1
  fi

  if grep -qi "pong" /tmp/agent_zero_resp.json; then
    ok "Agent Zero responded successfully and appears to be generating completions."
  else
    ok "Agent Zero responded with 200, but response didn't clearly contain 'pong'."
    warn "Check /tmp/agent_zero_resp.json to confirm the content."
  fi
}

########################################
# Check OpenWebUI                      #
########################################

check_openwebui() {
  echo "==> Checking OpenWebUI at: $OPENWEBUI_URL"

  local http_code
  http_code=$(curl -s -o /tmp/openwebui_resp.html -w "%{http_code}" \
    "$OPENWEBUI_URL" || true)

  if [ "$http_code" != "200" ]; then
    err "OpenWebUI returned HTTP $http_code"
    echo "     URL: $OPENWEBUI_URL"
    return 1
  fi

  ok "OpenWebUI main page is reachable (HTTP 200)."
}


########################################
# Main                                 #
########################################

main() {
  require_cmd curl

  echo "==================================="
  echo "  OLLAMA / AGENT ZERO / OPENWEBUI "
  echo "         HEALTH CHECK              "
  echo "==================================="
  echo "OLLAMA_URL      = $OLLAMA_URL"
  echo "AGENT_ZERO_URL  = $AGENT_ZERO_URL"
  echo "OPENWEBUI_URL   = $OPENWEBUI_URL"
  echo "AGENT_ZERO_MODEL= $AGENT_ZERO_MODEL"
  echo

  local failures=0

  if ! check_ollama; then
    failures=$((failures+1))
  fi

  echo

  if ! check_agent_zero; then
    failures=$((failures+1))
  fi

  echo

  if ! check_openwebui; then
    failures=$((failures+1))
  fi

  echo
  if [ "$failures" -eq 0 ]; then
    ok "All checks passed. Stack looks healthy."
  else
    err "$failures check(s) failed. See messages above and /tmp/*.json for details."
    exit 1
  fi
}

main "$@"
