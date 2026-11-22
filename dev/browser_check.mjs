// Renders every dashboard view headlessly and fails on card errors; env: HA_BASE, HA_USER, HA_PASS, HA_TOKEN.
import { chromium } from "playwright-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BASE = process.env.HA_BASE;
const SETTLE_MS = Number(process.env.HA_SETTLE_MS || 4000);
const CARD_ERRORS = /ButtonCardJSTemplateError/;
const PAGE_TEXT_ERRORS = /Configuration error|Custom element doesn't exist/;

function browserPath() {
  if (process.env.PW_CHROMIUM) return process.env.PW_CHROMIUM;
  const own = chromium.executablePath();
  if (fs.existsSync(own)) return own;
  const cache = path.join(os.homedir(), "Library/Caches/ms-playwright");
  const dirs = fs.existsSync(cache) ? fs.readdirSync(cache).filter((d) => /^chromium-\d+$/.test(d)).sort().reverse() : [];
  for (const d of dirs) {
    const app = path.join(cache, d, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
    if (fs.existsSync(app)) return app;
  }
  throw new Error("no Chromium found; set PW_CHROMIUM");
}

function wsCalls() {
  const ws = new WebSocket(BASE.replace(/^http/, "ws") + "/api/websocket");
  let seq = 0;
  const pending = new Map();
  const ready = new Promise((resolve, reject) => {
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === "auth_required") ws.send(JSON.stringify({ type: "auth", access_token: process.env.HA_TOKEN }));
      else if (msg.type === "auth_ok") resolve();
      else if (msg.type === "auth_invalid") reject(new Error("websocket auth rejected"));
      else if (pending.has(msg.id)) pending.get(msg.id)(msg);
    };
    ws.onerror = () => reject(new Error("websocket error"));
  });
  const call = (payload) => new Promise((resolve) => {
    const id = ++seq;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, ...payload }));
  });
  return { ready, call, close: () => ws.close() };
}

async function listViews() {
  const { ready, call, close } = wsCalls();
  await ready;
  const targets = [];
  const dashboards = (await call({ type: "lovelace/dashboards/list" })).result;
  for (const d of dashboards) {
    const cfg = await call({ type: "lovelace/config", url_path: d.url_path });
    if (!cfg.success) continue;
    (cfg.result.views || []).forEach((v, i) => targets.push({ dash: d.url_path, view: v.path ?? String(i) }));
  }
  close();
  return targets;
}

const pageTextErrors = () => {
  const found = [];
  const walk = (root) => {
    for (const el of root.querySelectorAll("*")) if (el.shadowRoot) walk(el.shadowRoot);
    for (const card of root.querySelectorAll("hui-error-card")) found.push((card.shadowRoot?.textContent || card.textContent || "").trim().slice(0, 120));
  };
  walk(document.querySelector("home-assistant").shadowRoot);
  return found;
};

const targets = await listViews();
const browser = await chromium.launch({ executablePath: browserPath(), headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
let errors = [];
page.on("console", (m) => { if (m.type() === "error" && CARD_ERRORS.test(m.text())) errors.push(m.text().slice(0, 160)); });
page.on("pageerror", (e) => errors.push("pageerror: " + String(e).slice(0, 160)));

await page.goto(BASE + "/");
await page.fill("input[name=username]", process.env.HA_USER);
await page.fill("input[name=password]", process.env.HA_PASS);
await page.getByRole("button", { name: /log in/i }).click();
await page.waitForURL((u) => !u.pathname.startsWith("/auth"), { timeout: 30000 });

let failed = 0;
for (const t of targets) {
  errors = [];
  await page.goto(`${BASE}/${t.dash}/${t.view}`);
  await page.waitForTimeout(SETTLE_MS);
  const rendered = (await page.evaluate(pageTextErrors)).filter((x) => PAGE_TEXT_ERRORS.test(x));
  const all = [...new Set([...errors, ...rendered])];
  console.log(`${all.length ? "FAIL" : "ok  "} ${t.dash}/${t.view}${all.length ? ": " + all.join(" | ") : ""}`);
  if (all.length) failed++;
}
await browser.close();
console.log(`${targets.length} views, ${failed} with errors`);
process.exit(failed ? 1 : 0);
