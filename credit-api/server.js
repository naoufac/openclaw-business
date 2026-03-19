/**
 * credit-api/server.js
 * OpenClaw Business — Credit Tracking API
 *
 * Runs as a container on port 3100.
 * Client containers call this API to check credits before each request.
 * Also syncs limits with OpenRouter and exposes management endpoints.
 */

"use strict";

const express = require("express");
const rateLimit = require("express-rate-limit");
const Database = require("better-sqlite3");
const fetch = require("node-fetch");
const path = require("path");
const fs = require("fs");

const PORT = process.env.PORT || 3100;
const PROVISIONING_KEY = process.env.OPENROUTER_PROVISIONING_KEY || "";
const DATA_DIR = path.join(__dirname, "data");
const DB_PATH = path.join(DATA_DIR, "credits.db");

// ── Ensure data directory exists ──
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

// ── Database setup ──
const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    name         TEXT PRIMARY KEY,
    or_hash      TEXT UNIQUE,
    tier         TEXT NOT NULL DEFAULT 'standard',
    credit_limit REAL NOT NULL DEFAULT 8,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    paused       INTEGER NOT NULL DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS usage_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL,
    amount      REAL NOT NULL,
    description TEXT,
    recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS balance_cache (
    username       TEXT PRIMARY KEY,
    limit_total    REAL,
    limit_remaining REAL,
    last_synced    TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// ── Prepared statements ──
const stmts = {
  upsertUser: db.prepare(`
    INSERT INTO users (name, or_hash, tier, credit_limit)
    VALUES (@name, @or_hash, @tier, @credit_limit)
    ON CONFLICT(name) DO UPDATE SET
      or_hash      = excluded.or_hash,
      tier         = excluded.tier,
      credit_limit = excluded.credit_limit
  `),
  getUser: db.prepare("SELECT * FROM users WHERE name = ?"),
  listUsers: db.prepare("SELECT * FROM users ORDER BY created_at DESC"),
  logUsage: db.prepare(`
    INSERT INTO usage_log (username, amount, description)
    VALUES (?, ?, ?)
  `),
  upsertBalance: db.prepare(`
    INSERT INTO balance_cache (username, limit_total, limit_remaining, last_synced)
    VALUES (@username, @limit_total, @limit_remaining, datetime('now'))
    ON CONFLICT(username) DO UPDATE SET
      limit_total      = excluded.limit_total,
      limit_remaining  = excluded.limit_remaining,
      last_synced      = excluded.last_synced
  `),
  getBalance: db.prepare("SELECT * FROM balance_cache WHERE username = ?"),
  setPaused: db.prepare("UPDATE users SET paused = ? WHERE name = ?"),
};

// ── Helpers ──
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

async function syncBalance(username) {
  const user = stmts.getUser.get(username);
  if (!user || !user.or_hash) return null;
  try {
    const data = await orFetch(`/keys/${user.or_hash}`);
    const balance = {
      username,
      limit_total: data.limit ?? user.credit_limit,
      limit_remaining: data.limit_remaining ?? 0,
    };
    stmts.upsertBalance.run(balance);
    return balance;
  } catch (e) {
    console.error(`Balance sync failed for ${username}:`, e.message);
    return stmts.getBalance.get(username);
  }
}

// ── Express app ──
const app = express();
app.use(express.json());

// Rate limiting — this API is internal (Docker network only) but we still
// protect against misconfigured or compromised containers flooding it.
const limiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  max: 120,             // 120 requests/minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests — slow down" },
});
app.use(limiter);

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", uptime: process.uptime(), ts: new Date().toISOString() });
});

// Register / update a user
app.post("/users", (req, res) => {
  const { name, or_hash, tier = "standard", credit_limit = 8 } = req.body;
  if (!name || !or_hash) return res.status(400).json({ error: "name and or_hash required" });
  stmts.upsertUser.run({ name: name.toLowerCase(), or_hash, tier, credit_limit });
  res.json({ ok: true });
});

// List all users
app.get("/users", (_req, res) => {
  const users = stmts.listUsers.all();
  res.json(users);
});

// Get user balance (sync from OpenRouter)
app.get("/users/:name/balance", async (req, res) => {
  const name = req.params.name.toLowerCase();
  const cached = stmts.getBalance.get(name);

  // Return cached value if fresh (< 5 minutes old)
  if (cached) {
    const ageMs = Date.now() - new Date(cached.last_synced).getTime();
    if (ageMs < 5 * 60 * 1000) return res.json(cached);
  }

  const balance = await syncBalance(name);
  if (!balance) return res.status(404).json({ error: "User not found" });
  res.json(balance);
});

// Check if a user has credits (lightweight, returns boolean)
app.get("/users/:name/has-credits", async (req, res) => {
  const name = req.params.name.toLowerCase();
  const user = stmts.getUser.get(name);
  if (!user) return res.json({ allowed: false, reason: "unknown_user" });
  if (user.paused) return res.json({ allowed: false, reason: "paused" });

  const balance = await syncBalance(name);
  if (!balance) return res.json({ allowed: true, reason: "sync_failed_allowing" });

  const allowed = balance.limit_remaining > 0;
  res.json({ allowed, remaining: balance.limit_remaining, reason: allowed ? "ok" : "no_credits" });
});

// Record usage
app.post("/users/:name/usage", (req, res) => {
  const name = req.params.name.toLowerCase();
  const { amount, description } = req.body;
  if (!amount) return res.status(400).json({ error: "amount required" });
  stmts.logUsage.run(name, amount, description || "api_call");
  res.json({ ok: true });
});

// Force sync from OpenRouter
app.post("/users/:name/sync", async (req, res) => {
  const name = req.params.name.toLowerCase();
  const balance = await syncBalance(name);
  if (!balance) return res.status(404).json({ error: "User not found or sync failed" });
  res.json(balance);
});

// Pause a user
app.post("/users/:name/pause", (req, res) => {
  const name = req.params.name.toLowerCase();
  stmts.setPaused.run(1, name);
  res.json({ ok: true, status: "paused" });
});

// Resume a user
app.post("/users/:name/resume", (req, res) => {
  const name = req.params.name.toLowerCase();
  stmts.setPaused.run(0, name);
  res.json({ ok: true, status: "active" });
});

// Usage history for a user
app.get("/users/:name/usage", (req, res) => {
  const name = req.params.name.toLowerCase();
  const rows = db
    .prepare("SELECT * FROM usage_log WHERE username = ? ORDER BY recorded_at DESC LIMIT 100")
    .all(name);
  res.json(rows);
});

// Summary stats (for admin dashboard)
app.get("/stats", (_req, res) => {
  const total = db.prepare("SELECT COUNT(*) as n FROM users").get().n;
  const active = db.prepare("SELECT COUNT(*) as n FROM users WHERE paused = 0").get().n;
  const paused = db.prepare("SELECT COUNT(*) as n FROM users WHERE paused = 1").get().n;
  const tiers = db
    .prepare("SELECT tier, COUNT(*) as n FROM users GROUP BY tier")
    .all();
  res.json({ total, active, paused, tiers });
});

// ── Start ──
app.listen(PORT, () => {
  console.log(`✅ Credit API running on port ${PORT}`);
  console.log(`   DB: ${DB_PATH}`);
  console.log(`   OpenRouter key: ${PROVISIONING_KEY ? "✅ set" : "❌ NOT SET"}`);
});
