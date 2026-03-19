# 📋 OpenClaw Business - Operational Guidelines

> Standard procedures, quality standards, and security protocols for running the OpenClaw Business automation service.

---

## Table of Contents

1. [Client Onboarding Procedures](#client-onboarding-procedures)
2. [Quality Standards](#quality-standards)
3. [Security Protocols](#security-protocols)
4. [Communication Templates](#communication-templates)

---

## 🤝 Client Onboarding Procedures

### Pre-Onboarding Checklist

Before starting any client onboarding, verify:

- [ ] Client has selected a pricing tier
- [ ] Payment has been received (or payment plan agreed)
- [ ] Client has created a Telegram bot via @BotFather
- [ ] Client has provided their Telegram bot token
- [ ] You have their preferred name for the AI assistant
- [ ] VPS has sufficient resources for new client

### Onboarding Workflow

#### Step 1: Initial Contact (Day 0)

```
Welcome! 🦞

I'm excited to set up your personal AI assistant! Before we begin, I'll need:

1. Your preferred name for the assistant (e.g., "Clara", "Max")
2. Your Telegram bot token (created via @BotFather)
3. Selected pricing tier (Standard/Premium/Pro)

Once you provide these, I'll have your assistant up and running within 30 minutes!
```

#### Step 2: Account Creation (Day 0)

```bash
# 1. Verify VPS resources
docker stats --no-stream

# 2. Add the new client
chmod +x add-claw.sh
./add-claw.sh [client-name] "[BOT_TOKEN]" [tier] [ram-gb]

# 3. Verify container is running
docker ps | grep claw-[client-name]

# 4. Set up credit limit
./manage-credits.sh topup [client-name] [monthly-allowance]
```

#### Step 3: Handover (Day 0)

Send the client their welcome message (see templates below).

#### Step 4: Follow-Up (Day 1-3)

- Check if the bot is responding
- Verify credit usage is within limits
- Ask for feedback

---

## ✅ Quality Standards

### Service Availability

| Metric | Target |
|--------|--------|
| **Uptime** | 99.5% (excluding scheduled maintenance) |
| **Response Time** | <5 seconds for bot commands |
| **First Response** | Within 24 hours for support requests |

### Setup Quality

- [ ] All containers start within 5 minutes
- [ ] Docker logs show no errors on startup
- [ ] Bot responds to /start command
- [ ] Environment variables correctly set
- [ ] Credit limits properly configured

### Monitoring Standards

```bash
# Daily checks (recommended)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker stats --no-stream
./manage-credits.sh list
```

### Maintenance Windows

- **Scheduled**: Weekly Sunday 2-4 AM UTC
- **Emergency**: As needed with client notification

---

## 🔒 Security Protocols

### Container Security

All client containers MUST run with:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
```

### Credential Management

| Credential | Storage | Rotation |
|------------|---------|----------|
| OpenRouter Key | VPS .env file | Monthly |
| Bot Tokens | VPS .env file | Per client |
| SSH Keys | Client's responsibility | Quarterly |

### Access Control

```bash
# Never share your .env file
# Use .env.template for setup

# Restrict SSH access
# Use key-based authentication only

# Firewall rules (example)
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### Data Privacy

- **No cross-client data access**: Each container has its own volume
- **No data retention**: Client can request full data deletion
- **Encrypted at rest**: Use encrypted volumes for sensitive data

### Incident Response

```
If security incident detected:

1. ISOLATE - Stop affected container
   docker stop claw-[client]

2. ASSESS - Check logs for breach
   docker logs claw-[client] > incident-[date].log

3. NOTIFY - Inform affected client within 24h

4. REMEDIATE - Patch vulnerability
   docker rm claw-[client]
   ./add-claw.sh [client] "[token]" [tier] [ram]

5. DOCUMENT - Record incident details
```

---

## 💬 Communication Templates

### Welcome Message (New Client)

```
🧡 Welcome to OpenClaw Business!

Hi [CLIENT_NAME]! Your personal AI assistant "[ASSISTANT_NAME]" is now live!

📱 How to use:
- Open Telegram and search for your bot
- Send /start to begin
- Try asking: "What's the weather?"

⚙️ Your plan: [TIER]
💰 Monthly credits: $[AMOUNT]
📊 Current balance: $[BALANCE]

Need help? Just reply to this message!
```

### Payment Reminder (Day 25)

```
📢 Credit Reminder

Hi [CLIENT_NAME]! Your current balance is $[BALANCE].

Your plan includes $[MONTHLY_CREDITS] credits/month.
To continue without interruption, please top up before the 1st.

You can pay via [PAYMENT_METHOD] and I'll apply the credits.
```

### Service Outage Notice

```
⚠️ Service Notice

Hi [CLIENT_NAME],

We're currently performing maintenance on our servers.
Your assistant will be unavailable for approximately [TIME].

We apologize for the inconvenience and expect full service restoration by [TIME].

Thank you for your patience!
```

### Suspension Notice (Non-Payment)

```
📋 Account Notice

Hi [CLIENT_NAME],

Your account balance is now $[BALANCE], which is below the minimum threshold.

Service will be paused in 48 hours unless payment is received.
To maintain your assistant, please top up by [DATE].

Current balance: $[BALANCE]
Required: $[MONTHLY_AMOUNT]

Reply with payment confirmation and I'll restore access immediately.
```

### Cancellation Confirmation

```
✅ Cancellation Confirmed

Hi [CLIENT_NAME],

Your OpenClaw Business service has been cancelled as requested.

📦 Data retention: 30 days
🗑️ After [DATE], all data will be permanently deleted

It was great serving you! If you ever need AI assistance again, we're here.

Best wishes,
The OpenClaw Team
```

---

## 📊 Client Information Template

Maintain a record for each client:

```markdown
# Client: [NAME]
## Contact
- Telegram: @[username]
- Email: [email]

## Service
- Tier: [Standard/Premium/Pro]
- Start Date: [YYYY-MM-DD]
- Monthly Cost: $[amount]
- Bot Username: @[bot_username]

## Technical
- Container: claw-[name]
- RAM: [X]GB
- OpenRouter Key: [last 4 digits only]
- Monthly Limit: $[amount]

## Billing
- Payment Method: [details]
- Next Payment: [YYYY-MM-DD]
- Notes: [any special requirements]
```

---

## 🛠️ Troubleshooting Reference

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Bot not responding | Container stopped | `docker restart claw-[name]` |
| Out of credits | API limit reached | Top up via `manage-credits.sh` |
| Container OOM | Too much RAM | Upgrade tier or optimize |
| Permission denied | Security settings | Check container security_opt |

---

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-20 | Initial operational guidelines |

---

*Follow these guidelines to ensure consistent, secure, and high-quality service delivery.*
