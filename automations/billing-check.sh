#!/bin/bash
# ============================================================
#  automations/billing-check.sh
#  Run daily (e.g., at 9 AM) to:
#    1. Check every user's remaining credits via OpenRouter
#    2. Send reminder to admin for users with < 20% remaining
#    3. Auto-pause users whose credits are fully exhausted
#    4. Log results to ./data/billing.log
#
#  Usage:
#    ./automations/billing-check.sh
#
#  Cron example (daily at 9 AM):
#    0 9 * * * /opt/claw-server/automations/billing-check.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/data/billing.log"
KEY_REGISTRY="$PROJECT_DIR/data/key-registry.txt"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"

log() { echo "[$DATE] $*" | tee -a "$LOG_FILE"; }

send_alert() {
  local msg="$1"
  if [ -n "$ALERT_BOT_TOKEN" ] && [ -n "$ALERT_CHAT_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${ALERT_CHAT_ID}" \
      -d "text=${msg}" > /dev/null 2>&1 || true
  fi
}

[ -z "$OPENROUTER_PROVISIONING_KEY" ] && { log "❌ Missing OPENROUTER_PROVISIONING_KEY"; exit 1; }
[ ! -f "$KEY_REGISTRY" ] && { log "⚠️ key-registry.txt not found — no users to check"; exit 0; }

log "──── Billing check started ────"

LOW_CREDIT_USERS=""
ZERO_CREDIT_USERS=""

while IFS='|' read -r name hash tier ram created_at; do
  [ -z "$name" ] && continue

  RESPONSE=$(curl -s "https://openrouter.ai/api/v1/keys/$hash" \
    -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY")

  LIMIT=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('limit',0) or 0)" 2>/dev/null || echo "0")
  REMAINING=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('limit_remaining',0) or 0)" 2>/dev/null || echo "0")
  DISABLED=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('disabled',False))" 2>/dev/null || echo "False")

  # Calculate percentage
  if [ "$LIMIT" != "0" ] && [ "$LIMIT" != "None" ]; then
    PCT=$(python3 -c "print(round(float('$REMAINING') / float('$LIMIT') * 100))" 2>/dev/null || echo "?")
  else
    PCT="?"
  fi

  log "$name ($tier): \$${REMAINING} / \$${LIMIT} remaining (${PCT}%) — ${DISABLED}"

  # Check for low credits (< 20%)
  if [ "$PCT" != "?" ] && [ "$PCT" -lt 20 ] && [ "$PCT" -gt 0 ]; then
    LOW_CREDIT_USERS="${LOW_CREDIT_USERS}\n• ${name} (${tier}): \$${REMAINING} left (${PCT}%)"
  fi

  # Check for zero credits — auto-pause
  if [ "$PCT" = "0" ] || { [ "$PCT" != "?" ] && [ "$PCT" -le 0 ]; }; then
    if [ "$DISABLED" = "False" ]; then
      log "⏸️ Auto-pausing $name (no credits remaining)"
      curl -s -X PATCH "https://openrouter.ai/api/v1/keys/$hash" \
        -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
        -H "Content-Type: application/json" \
        -d '{"disabled": true}' > /dev/null
      docker stop "claw-${name}" 2>/dev/null || true
      ZERO_CREDIT_USERS="${ZERO_CREDIT_USERS}\n• ${name} (${tier}) — AUTO-PAUSED"
    fi
  fi
done < "$KEY_REGISTRY"

# Send summary alert
ALERT=""
if [ -n "$LOW_CREDIT_USERS" ]; then
  ALERT="${ALERT}⚠️ Low credits:%0A${LOW_CREDIT_USERS}%0A%0A"
fi
if [ -n "$ZERO_CREDIT_USERS" ]; then
  ALERT="${ALERT}🛑 Auto-paused (zero credits):%0A${ZERO_CREDIT_USERS}%0A%0A"
fi

if [ -n "$ALERT" ]; then
  send_alert "💰 OpenClaw Billing Alert%0A${ALERT}Top up via: ./manage-credits.sh topup <name> <amount>"
fi

log "──── Billing check complete ────"
