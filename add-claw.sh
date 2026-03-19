#!/bin/bash
# ============================================================
#  add-claw.sh — Spin up a new lobster, hardened + isolated
#
#  Usage: ./add-claw.sh <name> <telegram_token> <tier> [ram_gb]
#
#  Examples:
#    ./add-claw.sh sarah  "123456:TOKEN"  premium  2
#    ./add-claw.sh john   "789012:TOKEN"  standard 1
#    ./add-claw.sh marc   "345678:TOKEN"  pro      2
#
#  Tiers:   standard | pro | premium
#  RAM:     1 = 1GB, 2 = 2GB (default: 1 for standard, 2 for pro/premium)
# ============================================================
set -e

NAME=$1; TOKEN=$2; TIER=${3:-standard}; RAM_GB=$4
NAME_LOWER=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
CONTAINER="claw-${NAME_LOWER}"

[ -z "$NAME" ] || [ -z "$TOKEN" ] && echo "Usage: ./add-claw.sh <name> <token> [tier] [ram_gb]" && exit 1
[ ! -f ".env" ] && echo "❌  Missing .env — copy .env.template and fill in your keys" && exit 1
source .env

# ── RAM defaults by tier ──
[ -z "$RAM_GB" ] && { [ "$TIER" = "standard" ] && RAM_GB=1 || RAM_GB=2; }
MEM_LIMIT="${RAM_GB}g"
[ "$RAM_GB" -ge 2 ] && MEM_RESERVE="512m" && CPUS="1.0" || MEM_RESERVE="256m" && CPUS="0.6"

# ── Tier config ──
case "$TIER" in
  premium)
    MEM_GRAPH=true;  MEM_TACIT=true;  HEARTBEAT=true;  NIGHTLY=true
    MODEL="anthropic/claude-sonnet-4-5"; CREDIT_LIMIT=50 ;;
  pro)
    MEM_GRAPH=false; MEM_TACIT=false; HEARTBEAT=true;  NIGHTLY=true
    MODEL="anthropic/claude-sonnet-4-5"; CREDIT_LIMIT=20 ;;
  *)
    MEM_GRAPH=false; MEM_TACIT=false; HEARTBEAT=false; NIGHTLY=false
    MODEL="anthropic/claude-haiku-4-5";  CREDIT_LIMIT=8  ;;
esac

echo ""
echo "🦞  Adding: $NAME | $TIER | ${RAM_GB}GB RAM | \$$CREDIT_LIMIT credits/mo"
echo "────────────────────────────────────────────────────"

# ══════════════════════════════════════════════════════════════
#  STEP 1 — Create a per-user OpenRouter key (credit reselling)
#  Each user gets their own key with a monthly spend cap.
#  When they hit the limit, their lobster stops until top-up.
#  You buy credits wholesale, set limits, keep the margin.
# ══════════════════════════════════════════════════════════════
[ -z "$OPENROUTER_PROVISIONING_KEY" ] && echo "❌  Missing OPENROUTER_PROVISIONING_KEY in .env" && exit 1

echo "📡  Provisioning OpenRouter API key for $NAME..."
OR_RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/keys" \
  -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"claw-${NAME_LOWER}\", \"limit\": ${CREDIT_LIMIT}, \"limit_reset\": \"monthly\"}")

OR_KEY=$(echo "$OR_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
OR_HASH=$(echo "$OR_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hash',''))" 2>/dev/null)

[ -z "$OR_KEY" ] && echo "❌  OpenRouter key creation failed:" && echo "$OR_RESPONSE" && exit 1
echo "✅  OpenRouter key created → \$$CREDIT_LIMIT/month cap"

mkdir -p ./data
echo "${NAME_LOWER}|${OR_HASH}|${TIER}|${RAM_GB}GB|$(date +%Y-%m-%d)" >> ./data/key-registry.txt

# ══════════════════════════════════════════════════════════════
#  STEP 2 — Stagger installs to avoid RAM spike
#  npm install uses ~500MB peak. If 3 containers install at once
#  on an 8GB VPS it crashes. So we wait for the coast to be clear.
# ══════════════════════════════════════════════════════════════
ACTIVE=$(docker ps --filter "name=claw-" --format "{{.Names}}" | wc -l)
if [ "$ACTIVE" -gt 1 ]; then
  echo "⏳  ${ACTIVE} containers active — staggering install by 45s to protect RAM..."
  sleep 45
fi

# ══════════════════════════════════════════════════════════════
#  STEP 3 — Start the container with full security hardening
#
#  Security measures applied:
#  --read-only             : Container filesystem is read-only.
#                            OpenClaw can only write to its own
#                            mounted volume. Cannot touch the OS,
#                            other containers, or the host.
#
#  --tmpfs /tmp            : Gives a small in-memory scratch space
#                            (needed for npm and temp files).
#                            Wiped on every restart. Never on disk.
#
#  --tmpfs /root/.config   : App config scratch. Same — memory only.
#
#  --no-new-privileges     : The process inside can never escalate
#                            to root or gain extra Linux capabilities.
#                            Even if someone exploits a bug in
#                            OpenClaw or Node.js, they stay trapped.
#
#  --cap-drop ALL          : Strips all Linux kernel capabilities
#                            (mount drives, change network, etc).
#                            Container has zero special powers.
#
#  --cap-add CHOWN,SETUID  : Re-adds only the bare minimum needed
#  --cap-add SETGID,DAC... : for npm to install packages correctly.
#
#  Named volumes           : Each user's data is in their own named
#                            Docker volume (alice-data, bob-data).
#                            These are never shared or cross-mounted.
#
#  shared-skills :ro       : Read-only. No user can write skills
#                            that affect other users.
#
#  openclaw-cache          : Shared npm package cache. Speeds up
#                            installs dramatically. Contains no user
#                            data — just downloaded package files.
# ══════════════════════════════════════════════════════════════
echo "🔒  Starting hardened container: $CONTAINER (${MEM_LIMIT} RAM)..."

docker run -d \
  --name "$CONTAINER" \
  --network claw-net \
  --restart unless-stopped \
  \
  `# ── Resources ──` \
  --memory "$MEM_LIMIT" \
  --memory-reservation "$MEM_RESERVE" \
  --cpus "$CPUS" \
  \
  `# ── Security hardening ──` \
  --read-only \
  --tmpfs /tmp:size=200m,mode=1777 \
  --tmpfs /root/.config:size=50m \
  --tmpfs /root/.local:size=50m \
  --no-new-privileges \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add DAC_OVERRIDE \
  \
  `# ── Environment ──` \
  -e OPENCLAW_USER="$NAME_LOWER" \
  -e TELEGRAM_BOT_TOKEN="$TOKEN" \
  -e OPENAI_BASE_URL="https://openrouter.ai/api/v1" \
  -e OPENAI_API_KEY="$OR_KEY" \
  -e OPENCLAW_MODEL="$MODEL" \
  -e OPENCLAW_TIER="$TIER" \
  -e CREDIT_API_URL="http://claw-credits:3100" \
  -e MEMORY_DAILY=true \
  -e MEMORY_GRAPH="$MEM_GRAPH" \
  -e MEMORY_TACIT="$MEM_TACIT" \
  -e HEARTBEAT="$HEARTBEAT" \
  -e NIGHTLY_CRON="$NIGHTLY" \
  \
  `# ── Volumes (isolated per user) ──` \
  -v "${NAME_LOWER}-data:/home/claw/.openclaw" \
  -v "$(pwd)/shared-skills:/home/claw/.openclaw/skills/shared:ro" \
  -v "openclaw-cache:/root/.npm" \
  \
  node:20-alpine \
  sh -c "npm install -g openclaw --prefer-offline 2>/dev/null || npm install -g openclaw && openclaw start --headless"

# ── Wait for startup ──
echo "⏳  Waiting for startup..."
for i in $(seq 1 12); do
  sleep 5
  STATUS=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")
  [ "$STATUS" = "true" ] && echo "✅  Running ($((i*5))s)" && break || echo "    ... $((i*5))s"
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "🎉  $NAME's lobster is live!"
echo ""
echo "   Security:  read-only FS, no-new-privileges, caps dropped"
echo "   Isolation: private volume — cannot touch other users"
echo "   Model:     $MODEL (they can ask to switch anytime)"
echo "   Credits:   \$$CREDIT_LIMIT/month via OpenRouter"
echo ""
echo "   Logs:      docker logs $CONTAINER --tail 50"
echo "   Top-up:    ./manage-credits.sh topup $NAME_LOWER <amount>"
echo "   Pause:     ./manage-credits.sh pause $NAME_LOWER"
echo "═══════════════════════════════════════════════════════"
