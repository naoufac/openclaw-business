# 🦞 OpenClaw Family Server — Full Setup Guide

Everything you need to run 3–5 personal AI assistants on one 8GB VPS.
Each person gets their own private lobster on Telegram. Fully isolated. Fully secure.

---

## What You Need Before Starting

| Thing | Where to get it |
|---|---|
| A VPS (8GB RAM, Ubuntu 22+) | Hetzner, DigitalOcean, Contabo |
| Docker installed on the VPS | Step 1 below |
| An OpenRouter account with funds | openrouter.ai |
| An OpenRouter **Provisioning Key** | openrouter.ai/settings/provisioning-keys |
| One Telegram bot token per user | @BotFather on Telegram |

---

## Step 1 — Install Docker on your VPS

SSH into your VPS, then run:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker --version   # should print a version number
```

---

## Step 2 — Upload these files to your VPS

From your local machine:

```bash
scp -r ./claw-server root@YOUR_VPS_IP:/opt/claw-server
ssh root@YOUR_VPS_IP
cd /opt/claw-server
```

Or clone / copy manually — the files you need on the VPS are:
```
/opt/claw-server/
  docker-compose.yml
  add-claw.sh
  manage-credits.sh
  .env.template
  shared-skills/      ← create this empty folder
  credit-api/         ← create this empty folder
  data/               ← created automatically
```

---

## Step 3 — Set up your .env file

```bash
cp .env.template .env
nano .env
```

The only thing you **must** fill in right now:
```
OPENROUTER_PROVISIONING_KEY=sk-or-v1-...
```

Everything else (bot tokens, per-user keys) is handled by `add-claw.sh`.

---

## Step 4 — Create the Docker network + start shared services

```bash
docker network create claw-net
docker compose up -d nginx credit-api
docker ps   # should show nginx and claw-credits running
```

---

## Step 5 — Add each person (one command each)

First get a Telegram bot for each person:
1. Open Telegram → message @BotFather
2. Send `/newbot` → pick any name
3. Copy the token (looks like `123456789:ABCdef...`)

Then run one command per person:

```bash
chmod +x add-claw.sh

./add-claw.sh sarah  "SARAH_BOT_TOKEN"   premium  2
./add-claw.sh john   "JOHN_BOT_TOKEN"    standard 1
./add-claw.sh marc   "MARC_BOT_TOKEN"    pro      2
```

That's it. Each person gets:
- Their own private lobster (isolated container + volume)
- Their own OpenRouter key with a monthly credit cap
- Full security hardening (read-only FS, no privilege escalation)

Tell them to open Telegram and message their bot.

---

## Day-to-Day Management

```bash
# See all running lobsters
docker ps

# Check someone's logs (useful if their bot stops responding)
docker logs claw-sarah --tail 50

# Restart one lobster
docker restart claw-sarah

# See RAM usage live
docker stats

# Stop everything (maintenance)
docker compose down

# Start everything back up
docker compose up -d
```

---

## Credit Management (OpenRouter reselling)

```bash
# See all users and their remaining credits
./manage-credits.sh list

# Check one user's balance
./manage-credits.sh balance sarah

# Top up someone's credits (e.g. they paid you $20)
./manage-credits.sh topup sarah 20

# Pause a user (non-payment, etc.)
./manage-credits.sh pause sarah

# Resume them
./manage-credits.sh resume sarah
```

---

## RAM Budget — What Fits on 8GB

| Service | RAM used |
|---|---|
| Ubuntu OS | ~400MB |
| Nginx | ~50MB |
| Credit API | ~100MB |
| 1× Premium user (2GB) | 2,000MB |
| 1× Pro user (2GB) | 2,000MB |
| 2× Standard users (1GB each) | 2,000MB |
| **Total** | **~6.5GB** ✅ |

Safe maximum: **2 premium + 1 pro + 2 standard** on 8GB.

---

## Security Summary

Every container runs with:

| Flag | What it means in plain English |
|---|---|
| `--read-only` | The container can't write anywhere except its own data volume |
| `--no-new-privileges` | Even if someone hacks the container, they can't become admin |
| `--cap-drop ALL` | All Linux special powers removed |
| Private named volume | Alice's data is physically inaccessible to Bob's container |
| `shared-skills :ro` | Read-only — no user can push malicious skills to others |

OpenClaw can rewrite its own brain freely. It cannot touch anyone else's.

---

## How the OpenRouter Credit Reselling Works

1. You fund your OpenRouter account (e.g. put in $100)
2. `add-claw.sh` creates a sub-key for each user with a monthly cap (e.g. $8 for standard)
3. That user's lobster uses ONLY their key — limited to their cap
4. You charge users $19–99/month, your actual cost is $8–50/month
5. Margin: ~40–60% gross per user
6. Users can ask their lobster to switch models anytime ("use GPT-4o", "switch to Gemini Flash")
   — they stay within their credit cap regardless of model chosen

---

## Troubleshooting

**Bot not responding?**
```bash
docker logs claw-USERNAME --tail 100
docker restart claw-USERNAME
```

**Container crashed on startup?**
```bash
docker logs claw-USERNAME
# Usually means npm install failed — retry:
docker rm claw-USERNAME
./add-claw.sh USERNAME "TOKEN" TIER RAM
```

**Out of memory during install?**
The stagger logic in add-claw.sh prevents this.
If it still happens: wait 2 minutes, then run add-claw.sh again.
The shared npm cache means the second attempt is much faster.

**Want to back up someone's memory?**
```bash
docker run --rm \
  -v USERNAME-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/USERNAME-$(date +%Y%m%d).tar.gz /data
```
