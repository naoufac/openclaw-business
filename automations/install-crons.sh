#!/bin/bash
# ============================================================
#  automations/install-crons.sh
#  One-time setup: installs all cron jobs for OpenClaw Business.
#
#  Jobs installed:
#    - Health check every 15 minutes
#    - Billing check daily at 9 AM
#    - Daily report at 8 AM
#    - Docker image cleanup weekly (Sunday 3 AM)
#
#  Usage:
#    chmod +x automations/install-crons.sh
#    sudo ./automations/install-crons.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Make scripts executable
chmod +x "$SCRIPT_DIR/health-check.sh"
chmod +x "$SCRIPT_DIR/billing-check.sh"
chmod +x "$SCRIPT_DIR/daily-report.sh"

echo "📋 Installing OpenClaw cron jobs..."
echo "   Project: $PROJECT_DIR"

# Build cron entries
HEALTH_CRON="*/15 * * * * $SCRIPT_DIR/health-check.sh >> $PROJECT_DIR/data/health.log 2>&1"
BILLING_CRON="0 9 * * * $SCRIPT_DIR/billing-check.sh >> $PROJECT_DIR/data/billing.log 2>&1"
REPORT_CRON="0 8 * * * $SCRIPT_DIR/daily-report.sh >> $PROJECT_DIR/data/daily-report.log 2>&1"
CLEANUP_CRON="0 3 * * 0 docker image prune -f >> $PROJECT_DIR/data/cleanup.log 2>&1"

# Get existing crontab (without our jobs)
EXISTING=$(crontab -l 2>/dev/null | grep -v "health-check\|billing-check\|daily-report\|docker image prune" || true)

# Write new crontab
(
  echo "$EXISTING"
  echo ""
  echo "# ── OpenClaw Business ──────────────────────────────────────"
  echo "$HEALTH_CRON"
  echo "$BILLING_CRON"
  echo "$REPORT_CRON"
  echo "$CLEANUP_CRON"
) | crontab -

echo ""
echo "✅ Cron jobs installed:"
echo "   Every 15 min  → health-check.sh (auto-restart stopped containers)"
echo "   Daily 9 AM    → billing-check.sh (check credits, auto-pause if exhausted)"
echo "   Daily 8 AM    → daily-report.sh (Telegram summary report)"
echo "   Sunday 3 AM   → docker image prune (cleanup)"
echo ""
echo "📋 Current crontab:"
crontab -l | grep -A5 "OpenClaw" || true
echo ""
echo "💡 To remove: crontab -e  (delete OpenClaw lines)"
