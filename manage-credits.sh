#!/bin/bash
# ============================================================
#  manage-credits.sh — View / top-up / pause user credits
#
#  Commands:
#    ./manage-credits.sh list                    # show all users + balance
#    ./manage-credits.sh topup sarah 20          # add $20 to sarah's limit
#    ./manage-credits.sh pause sarah             # disable sarah's key
#    ./manage-credits.sh resume sarah            # re-enable sarah's key
#    ./manage-credits.sh balance sarah           # check remaining credits
# ============================================================
set -e

CMD=$1; NAME=$2; AMOUNT=$3
[ ! -f ".env" ] && echo "Missing .env" && exit 1
source .env
[ -z "$OPENROUTER_PROVISIONING_KEY" ] && echo "Missing OPENROUTER_PROVISIONING_KEY" && exit 1

get_hash() {
  grep "^$1|" ./data/key-registry.txt | cut -d'|' -f2 | head -1
}

case "$CMD" in
  list)
    echo "🦞  All users:"
    echo "──────────────────────────────────────────"
    while IFS='|' read -r name hash tier ram date; do
      STATUS=$(curl -s "https://openrouter.ai/api/v1/keys/$hash" \
        -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('limit_remaining','?')} / {d.get('limit','?')} remaining, {'DISABLED' if d.get('disabled') else 'active'}\")" 2>/dev/null || echo "?")
      echo "  $name ($tier, $ram) — $STATUS"
    done < ./data/key-registry.txt
    ;;

  balance)
    HASH=$(get_hash "$NAME")
    [ -z "$HASH" ] && echo "User $NAME not found" && exit 1
    curl -s "https://openrouter.ai/api/v1/keys/$HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Credits remaining: \${d.get(\"limit_remaining\",\"?\")} / \${d.get(\"limit\",\"?\")}')"
    ;;

  topup)
    HASH=$(get_hash "$NAME")
    [ -z "$HASH" ] && echo "User $NAME not found" && exit 1
    [ -z "$AMOUNT" ] && echo "Usage: ./manage-credits.sh topup <n> <amount>" && exit 1
    # Get current limit, add to it
    CURRENT=$(curl -s "https://openrouter.ai/api/v1/keys/$HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" | \
      python3 -c "import sys,json; print(json.load(sys.stdin).get('limit',0))")
    NEW_LIMIT=$((CURRENT + AMOUNT))
    curl -s -X PATCH "https://openrouter.ai/api/v1/keys/$HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"limit\": $NEW_LIMIT}" > /dev/null
    echo "✅  $NAME topped up by \$$AMOUNT. New limit: \$$NEW_LIMIT"
    ;;

  pause)
    HASH=$(get_hash "$NAME")
    [ -z "$HASH" ] && echo "User $NAME not found" && exit 1
    curl -s -X PATCH "https://openrouter.ai/api/v1/keys/$HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
      -H "Content-Type: application/json" \
      -d '{"disabled": true}' > /dev/null
    echo "⏸️   $NAME's lobster paused (API key disabled)"
    ;;

  resume)
    HASH=$(get_hash "$NAME")
    [ -z "$HASH" ] && echo "User $NAME not found" && exit 1
    curl -s -X PATCH "https://openrouter.ai/api/v1/keys/$HASH" \
      -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
      -H "Content-Type: application/json" \
      -d '{"disabled": false}' > /dev/null
    echo "▶️   $NAME's lobster resumed"
    ;;

  *)
    echo "Commands: list | balance <n> | topup <n> <amount> | pause <n> | resume <n>"
    ;;
esac
