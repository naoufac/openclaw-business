/**
 * admin/server.js
 * OpenClaw Business — Admin Dashboard API
 *
 * Runs on port 3200. Provides:
 *   - Client management (list, add, pause, resume, remove)
 *   - Lead capture and pipeline
 *   - Revenue stats
 *   - Docker container health
 *
 * Mount /var/run/docker.sock to manage containers from within Docker.
 * Mount the host project root at /host for script execution.
 */

"use strict";

const express = require("express");
const rateLimit = require("express-rate-limit");
const Database = require("better-sqlite3");
const fetch = require("node-fetch");
const Docker = require("dockerode");
const path = require("path");
const fs = require("fs");
const { execSync, execFile } = require("child_process");

const PORT = process.env.PORT || 3200;
const PROVISIONING_KEY = process.env.OPENROUTER_PROVISIONING_KEY || "";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "changeme";
const DATA_DIR = process.env.DATA_DIR || "/data";
const HOST_DIR = process.env.HOST_DIR || "/host";
// key-registry.txt is in the host data/ folder, mounted at /data/registry/ in the admin container
const KEY_REGISTRY_DIR = process.env.KEY_REGISTRY_DIR || path.join(DATA_DIR, "registry");
const KEY_REGISTRY = path.join(KEY_REGISTRY_DIR, "key-registry.txt");
const DB_PATH = path.join(DATA_DIR, "admin.db");
const CREDIT_API_URL = process.env.CREDIT_API_URL || "http://credit-api:3100";

// ── Docker client ──
let docker;
try {
  docker = new Docker({ socketPath: "/var/run/docker.sock" });
} catch (_) {
  console.warn("⚠️  Docker socket not available — container actions disabled");
}

// ── Ensure data dir ──
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(KEY_REGISTRY_DIR)) fs.mkdirSync(KEY_REGISTRY_DIR, { recursive: true });

// ── Database ──
const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS leads (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    email      TEXT,
    telegram   TEXT,
    tier       TEXT DEFAULT 'standard',
    message    TEXT,
    status     TEXT NOT NULL DEFAULT 'new',
    source     TEXT DEFAULT 'landing_page',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS payments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL,
    amount      REAL NOT NULL,
    method      TEXT,
    reference   TEXT,
    note        TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    type        TEXT NOT NULL,
    username    TEXT,
    description TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// ── Helpers ──
function logEvent(type, username, description) {
  db.prepare("INSERT INTO events (type, username, description) VALUES (?, ?, ?)").run(
    type, username || null, description || null
  );
}

function readKeyRegistry() {
  if (!fs.existsSync(KEY_REGISTRY)) return [];
  return fs.readFileSync(KEY_REGISTRY, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [name, or_hash, tier, ram, created_at] = line.split("|");
      return { name, or_hash, tier, ram, created_at };
    });
}

async function orFetch(path, opts = {}) {
  if (!PROVISIONING_KEY) throw new Error("OPENROUTER_PROVISIONING_KEY not set");
  const res = await fetch(`https://openrouter.ai/api/v1${path}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${PROVISIONING_KEY}`,
      "Content-Type": "application/json",
      ...(opts.headers || {}),
    },
  });
  return res.json();
}

async function getDockerContainers() {
  if (!docker) return {};
  try {
    const containers = await docker.listContainers({ all: true });
    const map = {};
    for (const c of containers) {
      const name = c.Names[0]?.replace("/", "") || "";
      if (name.startsWith("claw-")) {
        map[name] = {
          id: c.Id.slice(0, 12),
          status: c.State,
          uptime: c.Status,
        };
      }
    }
    return map;
  } catch (e) {
    return {};
  }
}

async function getOrBalance(or_hash) {
  try {
    const data = await orFetch(`/keys/${or_hash}`);
    return {
      limit: data.limit ?? null,
      limit_remaining: data.limit_remaining ?? null,
      disabled: data.disabled ?? false,
    };
  } catch (_) {
    return { limit: null, limit_remaining: null, disabled: null };
  }
}

// ── Pricing tier map ──
const TIER_PRICE = { standard: 19, pro: 49, premium: 79 };
const TIER_COST  = { standard: 8,  pro: 20, premium: 50 };

// ── Auth middleware ──
// Password must be passed via the X-Admin-Password header only.
// Query-string passwords are intentionally not supported — they end up
// in server logs and browser history which would expose the credential.
function requireAuth(req, res, next) {
  const auth = req.headers["x-admin-password"];
  if (!auth || auth !== ADMIN_PASSWORD) {
    return res.status(401).json({ error: "Unauthorized. Pass X-Admin-Password header." });
  }
  next();
}

// ── Express app ──
const app = express();
app.use(express.json());

// Serve static dashboard
app.use(express.static(path.join(__dirname, "public")));

// Rate limiting for the API
const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests" },
});
app.use("/api/", apiLimiter);

// Stricter limit for the public lead-capture endpoint
const leadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many submissions — please try again later" },
});

// ─────────────────────────────────────────────────────────────────────
//  PUBLIC ROUTES
// ─────────────────────────────────────────────────────────────────────

app.get("/health", (_req, res) => {
  res.json({ status: "ok", uptime: process.uptime(), ts: new Date().toISOString() });
});

// Lead capture (public — from landing page)
app.post("/api/leads", leadLimiter, (req, res) => {
  const { name, email, telegram, tier, message, source } = req.body;
  if (!name) return res.status(400).json({ error: "name is required" });
  const row = db
    .prepare(`INSERT INTO leads (name, email, telegram, tier, message, source)
              VALUES (?, ?, ?, ?, ?, ?) RETURNING id`)
    .get(name, email || null, telegram || null, tier || "standard", message || null, source || "landing_page");
  logEvent("lead_captured", null, `New lead: ${name} (${tier || "standard"})`);
  res.status(201).json({ ok: true, id: row.id });
});

// ─────────────────────────────────────────────────────────────────────
//  PROTECTED ROUTES
// ─────────────────────────────────────────────────────────────────────

// ── Clients ──

app.get("/api/clients", requireAuth, async (req, res) => {
  const registry = readKeyRegistry();
  const containers = await getDockerContainers();

  const clients = await Promise.all(
    registry.map(async (u) => {
      const containerName = `claw-${u.name}`;
      const container = containers[containerName] || { status: "unknown", uptime: "unknown" };
      const balance = u.or_hash ? await getOrBalance(u.or_hash) : {};
      return {
        ...u,
        container: container.status,
        uptime: container.uptime,
        ...balance,
        monthly_price: TIER_PRICE[u.tier] ?? 19,
        monthly_cost: TIER_COST[u.tier] ?? 8,
      };
    })
  );

  res.json(clients);
});

app.post("/api/clients/:name/pause", requireAuth, async (req, res) => {
  const name = req.params.name.toLowerCase();
  const registry = readKeyRegistry();
  const user = registry.find((u) => u.name === name);
  if (!user) return res.status(404).json({ error: "Client not found" });

  // Pause OpenRouter key
  if (user.or_hash && PROVISIONING_KEY) {
    await orFetch(`/keys/${user.or_hash}`, {
      method: "PATCH",
      body: JSON.stringify({ disabled: true }),
    }).catch(() => {});
  }

  // Stop Docker container
  if (docker) {
    try {
      const container = docker.getContainer(`claw-${name}`);
      await container.stop();
    } catch (_) {}
  }

  // Notify credit-api
  fetch(`${CREDIT_API_URL}/users/${name}/pause`, { method: "POST" }).catch(() => {});

  logEvent("client_paused", name, `Client ${name} paused`);
  res.json({ ok: true });
});

app.post("/api/clients/:name/resume", requireAuth, async (req, res) => {
  const name = req.params.name.toLowerCase();
  const registry = readKeyRegistry();
  const user = registry.find((u) => u.name === name);
  if (!user) return res.status(404).json({ error: "Client not found" });

  // Re-enable OpenRouter key
  if (user.or_hash && PROVISIONING_KEY) {
    await orFetch(`/keys/${user.or_hash}`, {
      method: "PATCH",
      body: JSON.stringify({ disabled: false }),
    }).catch(() => {});
  }

  // Start Docker container
  if (docker) {
    try {
      const container = docker.getContainer(`claw-${name}`);
      await container.start();
    } catch (_) {}
  }

  fetch(`${CREDIT_API_URL}/users/${name}/resume`, { method: "POST" }).catch(() => {});

  logEvent("client_resumed", name, `Client ${name} resumed`);
  res.json({ ok: true });
});

app.post("/api/clients/:name/topup", requireAuth, async (req, res) => {
  const name = req.params.name.toLowerCase();
  const { amount, method, reference, note } = req.body;
  if (!amount || isNaN(parseFloat(amount))) {
    return res.status(400).json({ error: "amount must be a number" });
  }

  const registry = readKeyRegistry();
  const user = registry.find((u) => u.name === name);
  if (!user) return res.status(404).json({ error: "Client not found" });

  let newLimit = null;
  if (user.or_hash && PROVISIONING_KEY) {
    const current = await getOrBalance(user.or_hash);
    if (current.limit !== null) {
      newLimit = current.limit + parseFloat(amount);
      await orFetch(`/keys/${user.or_hash}`, {
        method: "PATCH",
        body: JSON.stringify({ limit: newLimit }),
      }).catch(() => {});
    }
  }

  // Record payment
  db.prepare(
    "INSERT INTO payments (username, amount, method, reference, note) VALUES (?, ?, ?, ?, ?)"
  ).run(name, parseFloat(amount), method || null, reference || null, note || null);

  logEvent("topup", name, `Topped up $${amount} for ${name}`);
  res.json({ ok: true, new_limit: newLimit });
});

app.get("/api/clients/:name/logs", requireAuth, async (req, res) => {
  const name = req.params.name.toLowerCase();
  if (!docker) return res.json({ logs: "" });
  try {
    const container = docker.getContainer(`claw-${name}`);
    const stream = await container.logs({ stdout: true, stderr: true, tail: 100 });
    res.json({ logs: stream.toString("utf8") });
  } catch (e) {
    res.status(404).json({ error: e.message });
  }
});

// ── Leads ──

app.get("/api/leads", requireAuth, (req, res) => {
  const { status } = req.query;
  const rows = status
    ? db.prepare("SELECT * FROM leads WHERE status = ? ORDER BY created_at DESC").all(status)
    : db.prepare("SELECT * FROM leads ORDER BY created_at DESC").all();
  res.json(rows);
});

app.patch("/api/leads/:id", requireAuth, (req, res) => {
  const { status, message } = req.body;
  const id = parseInt(req.params.id, 10);
  db.prepare(
    "UPDATE leads SET status = COALESCE(?, status), message = COALESCE(?, message), updated_at = datetime('now') WHERE id = ?"
  ).run(status || null, message || null, id);
  res.json({ ok: true });
});

// ── Payments ──

app.get("/api/payments", requireAuth, (req, res) => {
  const rows = db
    .prepare("SELECT * FROM payments ORDER BY created_at DESC LIMIT 200")
    .all();
  res.json(rows);
});

// ── Stats ──

app.get("/api/stats", requireAuth, async (req, res) => {
  const registry = readKeyRegistry();

  // Revenue calculations
  let mrr = 0;
  let mrc = 0;
  const tierCounts = {};
  for (const u of registry) {
    const tier = u.tier || "standard";
    mrr += TIER_PRICE[tier] ?? 19;
    mrc += TIER_COST[tier] ?? 8;
    tierCounts[tier] = (tierCounts[tier] || 0) + 1;
  }

  // Payments this month
  const monthPayments = db
    .prepare("SELECT SUM(amount) as total FROM payments WHERE created_at >= date('now','start of month')")
    .get();

  // Leads stats
  const leadStats = db
    .prepare("SELECT status, COUNT(*) as n FROM leads GROUP BY status")
    .all();

  // Events (last 20)
  const recentEvents = db
    .prepare("SELECT * FROM events ORDER BY created_at DESC LIMIT 20")
    .all();

  // Container health
  const containers = await getDockerContainers();
  const activeContainers = Object.values(containers).filter((c) => c.status === "running").length;

  res.json({
    clients: {
      total: registry.length,
      by_tier: tierCounts,
    },
    revenue: {
      mrr,
      mrc,
      margin: mrr - mrc,
      collected_this_month: monthPayments?.total ?? 0,
    },
    leads: leadStats,
    containers: {
      total: Object.keys(containers).length,
      running: activeContainers,
    },
    recent_events: recentEvents,
  });
});

// ── Events feed ──

app.get("/api/events", requireAuth, (req, res) => {
  const rows = db
    .prepare("SELECT * FROM events ORDER BY created_at DESC LIMIT 50")
    .all();
  res.json(rows);
});

// ─────────────────────────────────────────────────────────────────────
//  Start
// ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅ Admin dashboard running on port ${PORT}`);
  console.log(`   Data: ${DATA_DIR}`);
  console.log(`   Docker: ${docker ? "✅ connected" : "❌ not connected"}`);
  console.log(`   OpenRouter: ${PROVISIONING_KEY ? "✅ key set" : "❌ NOT SET"}`);
  logEvent("server_start", null, `Admin server started on port ${PORT}`);
});
