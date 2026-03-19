# 🦞 OpenClaw Business - AI Assistant Hosting Service

> Premium private AI assistant hosting for individuals and small teams. Each client gets their own isolated lobster on Telegram with full privacy and security.

---

## 🌟 Business Overview

**OpenClaw Business** provides managed AI assistant hosting services using OpenClaw - an open-source personal AI assistant framework. We deploy secure, isolated Docker containers for each client, giving them a private AI assistant accessible via Telegram.

### What We Offer

- **Private AI Assistants**: Each client gets their own Docker container with dedicated resources
- **Telegram Integration**: Clients interact with their AI via a personal Telegram bot
- **Credit Management**: Integrated OpenRouter API key management with monthly caps
- **Full Isolation**: Containerized architecture ensures complete data privacy between clients
- **Easy Scaling**: Add new clients with a single command

---

## 🏗️ Architecture

```
                                    ┌─────────────────┐
                                    │   VPS (8GB)     │
                                    │   Ubuntu 22+    │
                                    └────────┬────────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
              ┌─────▼─────┐           ┌──────▼──────┐          ┌──────▼──────┐
              │  Nginx    │           │ Credit API  │          │  Shared     │
              │  (Web)    │           │ (Node.js)   │          │  Skills     │
              │  :80/:443 │           │  :3100      │          │  (Read-only)│
              └─────┬─────┘           └──────┬──────┘          └─────────────┘
                    │                        │
        ┌───────────┼───────────┐            │
        │           │           │            │
   ┌────▼────┐ ┌────▼────┐ ┌────▼────┐      │
   │ Alice   │ │  Bob    │ │ Carol   │      │
   │ Premium │ │Standard │ │ Premium │      │
   │ (2GB)   │ │ (1GB)   │ │ (2GB)   │──────┘
   └─────────┘ └─────────┘ └─────────┘
        │           │           │
        └───────────┴───────────┘
                    │
            Telegram Bots
```

### Component Details

| Component | Description | RAM |
|-----------|-------------|-----|
| **Nginx** | Reverse proxy for web interfaces | ~50MB |
| **Credit API** | Tracks usage, manages OpenRouter keys | ~100MB |
| **Premium User** | Full-featured AI assistant | 2GB |
| **Standard User** | Basic AI assistant | 1GB |
| **OS + Buffer** | Ubuntu + safety margin | ~1.4GB |

### Security Features

Every container runs with:
- `--read-only` filesystem (cannot write outside volume)
- `--no-new-privileges` (prevents privilege escalation)
- `--cap-drop ALL` (removes all Linux capabilities)
- Private named volumes (user data physically isolated)
- Shared skills are read-only (no cross-user contamination)

---

## 💰 Pricing Tiers

| Tier | RAM | Features | Monthly Cost | Recommended Price |
|------|-----|----------|---------------|-------------------|
| **Standard** | 1GB | Basic AI, memory, limited models | ~$8/mo | $19/mo |
| **Premium** | 2GB | Full AI, memory, graphs, heartbeat, nightly cron | ~$20/mo | $49/mo |
| **Pro** | 2GB | Premium + priority support, custom skills | ~$20/mo | $79/mo |

### Cost Breakdown

- **OpenRouter API**: Primary cost driver
- **VPS**: ~$10-20/month for 8GB VPS (Hetzner, DigitalOcean, Contabo)
- **Margin**: 40-60% gross profit per user

---

## 🚀 Service Offerings

### 1. Family Plan (1-3 Users)
- Ideal for families or small groups
- Shared VPS resources
- Basic support
- Starting at $49/user/month

### 2. Professional Plan (4-10 Users)
- Dedicated or shared VPS
- Priority support
- Custom skill development
- Starting at $39/user/month

### 3. Enterprise Plan (10+ Users)
- Dedicated VPS per client or cluster
- 24/7 monitoring
- Custom integrations
- White-label options
- Contact for pricing

### Included Features (All Plans)

✅ Personal Telegram bot  
✅ Private container isolation  
✅ OpenRouter credit management  
✅ Model selection (Claude, GPT-4o, Gemini, Llama)  
✅ Daily memory & graph generation  
✅ Heartbeat monitoring (Premium+)  
✅ Nightly cron jobs (Premium+)  
✅ Backup & restore capabilities  

---

## 📋 How to Set Up New Clients

### Prerequisites

1. **VPS** (8GB RAM minimum, Ubuntu 22.04+)
   - Recommended: Hetzner, DigitalOcean, Contabo

2. **OpenRouter Account**
   - Sign up at [openrouter.ai](https://openrouter.ai)
   - Add funds to your account
   - Create a **Provisioning Key** in settings

3. **Telegram Bot Tokens**
   - One token per user from [@BotFather](https://t.me/BotFather)

### Step-by-Step Setup

#### 1. VPS Preparation

```bash
# SSH into your VPS
ssh root@YOUR_VPS_IP

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

#### 2. Upload Files

```bash
# From your local machine
scp -r ./openclaw-business root@YOUR_VPS_IP:/opt/claw-server
ssh root@YOUR_VPS_IP
cd /opt/claw-server
```

#### 3. Configure Environment

```bash
cp .env.template .env
nano .env
```

Set your OpenRouter provisioning key:
```
OPENROUTER_PROVISIONING_KEY=sk-or-v1-...
```

#### 4. Start Shared Services

```bash
docker network create claw-net
docker compose up -d nginx credit-api
```

#### 5. Add a New Client

```bash
chmod +x add-claw.sh

# Add a premium user (2GB RAM)
./add-claw.sh sarah "SARAH_BOT_TOKEN" premium 2

# Add a standard user (1GB RAM)
./add-claw.sh john "JOHN_BOT_TOKEN" standard 1
```

---

## 🔧 Management Commands

```bash
# List all running assistants
docker ps

# View logs for a specific user
docker logs claw-sarah --tail 50

# Restart a user's assistant
docker restart claw-sarah

# Check resource usage
docker stats

# List all users and balances
./manage-credits.sh list

# Check specific user balance
./manage-credits.sh balance sarah

# Top up credits (after payment)
./manage-credits.sh topup sarah 20

# Pause/Resume a user
./manage-credits.sh pause sarah
./manage-credits.sh resume sarah
```

---

## 📦 What's Included

### Core Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | Main orchestration file |
| `add-claw.sh` | Script to add new users |
| `manage-credits.sh` | Credit management CLI |
| `.env.template` | Environment template |
| `vps-setup-README.md` | Detailed VPS setup guide |

### Landing Pages

- `landing-page.html` - Main marketing page
- `landing-page 2.html` - Alternative variant

### Premium Features

- `premium-setup.sh` - Advanced setup automation

---

## 🔐 Security Best Practices

1. **Never commit `.env` files** - Use `.env.template` only
2. **Rotate API keys** periodically
3. **Monitor credit usage** weekly
4. **Keep Docker updated**
5. **Use strong SSH keys**
6. **Enable firewall** (ufw)

---

## 📞 Support

- **Documentation**: See `vps-setup-README.md` for detailed guides
- **Issues**: Open an issue on GitHub
- **Questions**: Contact support

---

## 🧡 License

This project is provided as-is for commercial use. OpenClaw is open-source.

---

*Built with ❤️ using OpenClaw*
