#!/bin/bash
# ============================================================
#  remove-claw.sh — Remove a client and their data
#
#  Usage:
#    ./remove-claw.sh <name> [--keep-data]
#
#  Examples:
#    ./remove-claw.sh sarah              # full removal
#    ./remove-claw.sh sarah --keep-data  # stop + unregister but keep volume
#
#  What it does:
#    1. Stops and removes the Docker container
#    2. Optionally removes the Docker volume (user data)
#    3. Revokes the OpenRouter API key
#    4. Removes entry from data/key-registry.txt
#
#  Use --keep-data if the client may return or you need their data.
#  To backup before removing:
#    docker run --rm -v sarah-data:/data -v $(pwd)/backups:/bak \
#      alpine tar czf /bak/sarah-$(date +%Y%m%d).tar.gz /data
# ============================================================
set -e

NAME=$1
KEEP_DATA=$2
NAME_LOWER=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
CONTAINER="claw-${NAME_LOWER}"
VOLUME="${NAME_LOWER}-data"

[ -z "$NAME" ] && echo "Usage: ./remove-claw.sh <name> [--keep-data]" && exit 1
[ ! -f ".env" ] && echo "❌  Missing .env" && exit 1
source .env

echo ""
echo "🗑️  Removing client: $NAME"
echo "────────────────────────────────────────────────────"

# Confirm
read -p "⚠️  This will permanently remove $NAME's container${KEEP_DATA:+ (data preserved)}. Continue? [y/N] " CONFIRM
[ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && echo "Cancelled." && exit 0

# ── Step 1: Stop & remove container ──
if docker inspect "$CONTAINER" > /dev/null 2>&1; then
  echo "🛑  Stopping container $CONTAINER..."
  docker stop "$CONTAINER" 2>/dev/null || true
  docker rm "$CONTAINER" 2>/dev/null || true
  echo "✅  Container removed"
else
  echo "ℹ️   Container $CONTAINER not found (already removed?)"
fi

# ── Step 2: Remove volume (unless --keep-data) ──
if [ "$KEEP_DATA" = "--keep-data" ]; then
  echo "💾  Keeping volume $VOLUME (--keep-data flag set)"
else
  if docker volume inspect "$VOLUME" > /dev/null 2>&1; then
    echo "🗑️   Removing volume $VOLUME..."
    docker volume rm "$VOLUME"
    echo "✅  Volume removed"
  else
    echo "ℹ️   Volume $VOLUME not found (already removed?)"
  fi
fi

# ── Step 3: Revoke OpenRouter key ──
if [ -f "./data/key-registry.txt" ] && [ -n "$OPENROUTER_PROVISIONING_KEY" ]; then
  OR_HASH=$(grep "^${NAME_LOWER}|" ./data/key-registry.txt | cut -d'|' -f2 | head -1)
  if [ -n "$OR_HASH" ]; then
    echo "🔑  Revoking OpenRouter key for $NAME..."
    REVOKE_RESP=$(curl -s -X DELETE "https://openrouter.ai/api/v1/keys/$OR_HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY")
    echo "✅  OpenRouter key revoked"
  fi
fi

# ── Step 4: Remove from key registry ──
if [ -f "./data/key-registry.txt" ]; then
  TMP=$(mktemp)
  grep -v "^${NAME_LOWER}|" ./data/key-registry.txt > "$TMP" || true
  mv "$TMP" ./data/key-registry.txt
  echo "✅  Removed from key-registry.txt"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅  $NAME has been removed."
if [ "$KEEP_DATA" = "--keep-data" ]; then
  echo ""
  echo "   Data volume $VOLUME is preserved."
  echo "   To delete it later: docker volume rm $VOLUME"
  echo "   To backup first:    docker run --rm -v $VOLUME:/data -v \$(pwd)/backups:/bak alpine tar czf /bak/${NAME_LOWER}-backup.tar.gz /data"
fi
echo "═══════════════════════════════════════════════════════"
