#!/bin/bash
# ============================================================
#  automations/health-check.sh
#  Run as a cron job every 15 minutes to:
#    1. Check all claw-* containers are running
#    2. Auto-restart any that have stopped
#    3. Log status to ./data/health.log
#    4. Alert via Telegram if a container is down (optional)
#
#  Usage:
#    ./automations/health-check.sh
#
#  Cron example (every 15 minutes):
#    */15 * * * * /opt/claw-server/automations/health-check.sh
#
#  Environment variables (optional):
#    ALERT_BOT_TOKEN  — Telegram bot token to send alerts to admin
#    ALERT_CHAT_ID    — Telegram chat ID of the admin
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/data/health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Load env if available
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"

log() { echo "[$DATE] $*" | tee -a "$LOG_FILE"; }

send_alert() {
  local msg="$1"
  if [ -n "$ALERT_BOT_TOKEN" ] && [ -n "$ALERT_CHAT_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${ALERT_CHAT_ID}" \
      -d "text=🚨 OpenClaw Health Alert%0A${msg}" > /dev/null 2>&1 || true
  fi
}

log "──── Health check started ────"

# Count total vs running claw containers
TOTAL=$(docker ps -a --filter "name=claw-" --format "{{.Names}}" | grep -v "^$" | wc -l)
RUNNING=$(docker ps --filter "name=claw-" --format "{{.Names}}" | grep -v "^$" | wc -l)

log "Containers: $RUNNING / $TOTAL running"

# Find stopped claw-* containers (exclude infra like claw-nginx, claw-credits, claw-admin)
STOPPED=$(docker ps -a --filter "name=claw-" --filter "status=exited" --format "{{.Names}}" \
  | grep -vE "^(claw-nginx|claw-credits|claw-admin)$" || true)

if [ -z "$STOPPED" ]; then
  log "✅ All user containers are healthy"
else
  for CONTAINER in $STOPPED; do
    log "⚠️  $CONTAINER is stopped — attempting restart..."
    if docker restart "$CONTAINER" > /dev/null 2>&1; then
      log "✅  $CONTAINER restarted successfully"
      send_alert "⚠️ Container $CONTAINER was stopped and has been auto-restarted."
    else
      log "❌  Failed to restart $CONTAINER"
      send_alert "❌ CRITICAL: Container $CONTAINER could not be restarted. Manual action required."
    fi
  done
fi

# Check disk space (warn if > 85%)
DISK_PCT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
if [ "$DISK_PCT" -gt 85 ]; then
  log "⚠️  Disk usage high: ${DISK_PCT}%"
  send_alert "⚠️ Disk usage is ${DISK_PCT}%. Consider cleaning up old Docker images."
fi

# Check RAM
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "?")
log "RAM available: ~${MEM_AVAIL}MB"

if [ "$MEM_AVAIL" != "?" ] && [ "$MEM_AVAIL" -lt 512 ]; then
  log "⚠️  Low memory: ${MEM_AVAIL}MB available"
  send_alert "⚠️ Low memory: ${MEM_AVAIL}MB available. May affect container stability."
fi

log "──── Health check complete ────"
