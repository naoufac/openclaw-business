#!/bin/bash
# ============================================================
#  automations/daily-report.sh
#  Run every morning (e.g., 8 AM) to send a daily summary
#  to the admin Telegram chat.
#
#  Report includes:
#    - Number of active clients
#    - Container statuses
#    - Credit balances for all users
#    - Revenue snapshot (MRR)
#    - Disk & RAM usage
#
#  Usage:
#    ./automations/daily-report.sh
#
#  Cron example (daily at 8 AM):
#    0 8 * * * /opt/claw-server/automations/daily-report.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_REGISTRY="$PROJECT_DIR/data/key-registry.txt"
LOG_FILE="$PROJECT_DIR/data/daily-report.log"
DATE=$(date '+%Y-%m-%d')
DATE_NICE=$(date '+%A, %B %-d %Y')

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

send_msg() {
  local msg="$1"
  if [ -n "$ALERT_BOT_TOKEN" ] && [ -n "$ALERT_CHAT_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${ALERT_CHAT_ID}" \
      --data-urlencode "text=${msg}" \
      -d "parse_mode=Markdown" > /dev/null 2>&1 || true
  fi
}

log "Generating daily report for $DATE"

# ── Container status ──
TOTAL=$(docker ps -a --filter "name=claw-" --format "{{.Names}}" 2>/dev/null | wc -l)
RUNNING=$(docker ps --filter "name=claw-" --format "{{.Names}}" 2>/dev/null | wc -l)

CONTAINER_LINES=""
while IFS= read -r name; do
  STATUS=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
  ICON=$([ "$STATUS" = "running" ] && echo "✅" || echo "❌")
  CONTAINER_LINES="${CONTAINER_LINES}${ICON} ${name}: ${STATUS}\n"
done < <(docker ps -a --filter "name=claw-" --format "{{.Names}}" 2>/dev/null | grep -v "^$" || true)

# ── Credit summary ──
CREDIT_LINES=""
TOTAL_CLIENTS=0
MRR=0

declare -A TIER_PRICE=([standard]=19 [pro]=49 [premium]=79)

if [ -f "$KEY_REGISTRY" ] && [ -n "$OPENROUTER_PROVISIONING_KEY" ]; then
  while IFS='|' read -r name hash tier ram created_at; do
    [ -z "$name" ] && continue
    TOTAL_CLIENTS=$((TOTAL_CLIENTS + 1))

    RESPONSE=$(curl -s "https://openrouter.ai/api/v1/keys/$hash" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" 2>/dev/null || echo "{}")
    REMAINING=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(float(d.get('limit_remaining',0) or 0),2))" 2>/dev/null || echo "?")
    LIMIT=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('limit',0) or 0)" 2>/dev/null || echo "?")

    PRICE=${TIER_PRICE[$tier]:-19}
    MRR=$((MRR + PRICE))

    CREDIT_LINES="${CREDIT_LINES}• ${name} (${tier}): \$${REMAINING} / \$${LIMIT}\n"
  done < "$KEY_REGISTRY"
fi

# ── System stats ──
DISK=$(df -h / | awk 'NR==2 {print $3 " used of " $2 " (" $5 ")"}')
MEM=$(free -m | awk 'NR==2 {printf "%.0fMB used / %.0fMB total", $3, $2}')

# ── Build report ──
REPORT="🦞 *OpenClaw Daily Report*
📅 ${DATE_NICE}

*Clients:* ${TOTAL_CLIENTS} total
*Containers:* ${RUNNING} / ${TOTAL} running

*Container Status:*
${CONTAINER_LINES}
*Credit Balances:*
${CREDIT_LINES}
*Revenue:*
• Estimated MRR: \$${MRR}/month

*System:*
• Disk: ${DISK}
• RAM: ${MEM}

_Run ./manage-credits.sh list for details_"

echo -e "$REPORT"
send_msg "$REPORT"
log "Report sent"
