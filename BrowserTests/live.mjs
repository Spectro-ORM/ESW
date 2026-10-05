import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { chromium } from "playwright";
import { checkClientDOM } from "./client.mjs";

const launcher = fileURLToPath(new URL("../scripts/live_demo.sh", import.meta.url));
const binDirectory = execFileSync(launcher, ["bin-path"], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();
const binary = join(binDirectory, "LiveDemo");
assert(existsSync(binary), "Build the demo first: ./scripts/live_demo.sh build");
const reservation = createServer();
await new Promise(resolve => reservation.listen(0, "127.0.0.1", resolve));
const port = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));
const url = `http://127.0.0.1:${port}`;
let serverLog = "";
const server = spawn(binary, [], { env: { ...process.env, PEREGRINE_PORT: String(port), PEREGRINE_HOST: "127.0.0.1" } });
server.stdout.on("data", data => { serverLog = (serverLog + data).slice(-20000); });
server.stderr.on("data", data => { serverLog = (serverLog + data).slice(-20000); });
let browser;
let page;
const errors = [];
const networkErrors = [];

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function eventually(check, message, timeout = 10000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { if (await check()) return; await delay(50); }
  throw new Error(message);
}

try {
  await eventually(async () => { try { return (await fetch(url)).ok; } catch { return false; } }, "Demo failed to start");
  const initial = await (await fetch(url)).text();
  assert.match(initial, /id="count"[^>]*>0<\/output>/, "Disconnected HTML renders before JavaScript");
  const systemChrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  browser = await chromium.launch({ headless: true, ...(existsSync(systemChrome) ? { executablePath: systemChrome } : {}) });
  const context = await browser.newContext({ viewport: { width: 1024, height: 1000 } });
  page = await context.newPage();
  await page.addInitScript(() => {
    window.liveErrors = [];
    document.addEventListener("esw:error", event => { if (window.liveErrors.length < 20) window.liveErrors.push(event.detail.message); }, true);
  });
  page.on("pageerror", error => errors.push(error.message));
  page.on("response", response => { if (response.status() >= 400) networkErrors.push([response.status(), response.url()]); });
  page.on("requestfailed", request => networkErrors.push([request.failure()?.errorText, request.url()]));
  await page.goto(url);
  const root = page.locator("[data-esw-live]");
  const connected = () => eventually(async () => await root.getAttribute("data-esw-state") === "connected", "Live connection did not become ready");
  const count = async value => eventually(async () => await page.locator("#count").textContent() === String(value), `Expected counter ${value}`);
  const idle = () => eventually(async () => await root.getAttribute("aria-busy") !== "true", "Event queue did not drain");
  await connected();
  await count(0);
  console.log("PASS: disconnected HTML and connected mount");
  const id = await root.getAttribute("data-esw-id");
  const csrf = await root.getAttribute("data-esw-csrf");
  const eventURL = url + await root.getAttribute("data-esw-event");
  const streamURL = url + await root.getAttribute("data-esw-stream");
  const headers = { "Content-Type": "application/json", "X-CSRF-Token": csrf };

  await page.locator("#name").fill("<Ada>");
  await page.locator("#name").evaluate(input => input.setSelectionRange(1, 3));
  const pushed = await context.request.post(`${url}/server-update/${id}`, { headers });
  assert.equal(pushed.status(), 204);
  await count(1);
  assert.equal(await page.locator("#name").inputValue(), "<Ada>");
  assert.deepEqual(await page.locator("#name").evaluate(input => [document.activeElement === input, input.selectionStart, input.selectionEnd]), [true, 1, 3]);

  await page.locator("#draft-first").fill("unsubmitted draft");
  await page.evaluate(() => { window.originalRow = document.querySelector("#row-first"); });
  await page.getByRole("button", { name: "Reverse", exact: true }).click();
  await idle();
  assert.equal(await page.locator("#rows li").first().getAttribute("id"), "row-third");
  assert.equal(await page.evaluate(() => window.originalRow === document.querySelector("#row-first")), true);
  assert.equal(await page.locator("#draft-first").inputValue(), "unsubmitted draft");
  assert.equal(await page.locator("#name").inputValue(), "<Ada>", "Blurred dirty inputs survive unrelated patches");

  for (let i = 0; i < 10; i++) await page.getByRole("button", { name: "Increase", exact: true }).click();
  await idle();
  await count(11);
  await page.getByRole("button", { name: "Say hello", exact: true }).click();
  await idle();
  assert.equal(await page.locator("#greeting").textContent(), "Hello, <Ada>!");
  assert.equal(await page.locator("#greeting ada").count(), 0);

  // Exercise delegated change bindings and repeated form fields.
  let changedPayload;
  page.on("request", request => {
    if (request.url() === eventURL && request.method() === "POST") changedPayload = request.postDataJSON();
  });
  await page.locator("#greeting-form").evaluate(form => {
    form.setAttribute("esw-change", "greet"); form.setAttribute("esw-debounce", "10");
    for (const value of ["one", "two"]) {
      const input = document.createElement("input"); input.type = "hidden"; input.name = "choices"; input.value = value; form.append(input);
    }
  });
  await page.locator("#name").fill("Grace");
  await eventually(async () => await page.locator("#greeting").textContent() === "Hello, Grace!", "Change event not rendered");
  await idle();
  assert.deepEqual(changedPayload.values.choices, ["one", "two"]);

  const revision = Number(await root.getAttribute("data-esw-revision"));
  const event = { id: "wire-retry", name: "increment", values: {}, baseRevision: revision };
  const first = await context.request.post(eventURL, { headers, data: event });
  assert.equal(first.status(), 200);
  const patch = await first.json();
  assert.equal(patch.render.statics, undefined);
  assert.equal(Object.keys(patch.render.dynamics).length, 1);
  const retry = await context.request.post(eventURL, { headers, data: event });
  assert.deepEqual(await retry.json(), patch);
  await count(12);

  console.log("PASS: events, forms, keyed DOM, focus, ownership and CSRF");
  assert.equal((await context.request.post(eventURL, { data: event })).status(), 403);
  assert.equal((await context.request.post(eventURL, { headers: { ...headers, "X-CSRF-Token": "wrong" }, data: event })).status(), 403);
  const outsider = await browser.newContext();
  assert.equal((await outsider.request.get(streamURL)).status(), 403);
  assert.equal((await outsider.request.post(eventURL, { headers, data: event })).status(), 403);
  await outsider.close();
  await count(12);

  await context.setOffline(true);
  await eventually(async () => await root.getAttribute("data-esw-state") === "disconnected", "Stream did not notice disconnect");
  const cookies = (await context.cookies()).map(cookie => `${cookie.name}=${cookie.value}`).join("; ");
  const offlinePush = await fetch(`${url}/server-update/${id}`, { method: "POST", headers: { ...headers, Cookie: cookies } });
  assert.equal(offlinePush.status, 204);
  await context.setOffline(false);
  await connected();
  await count(13);

  // Commit the event on the server, then lose its HTTP response. The browser
  // must retry the same ID and leave the count incremented exactly once.
  let dropped = false;
  await page.route("**/_live/*/event", async route => {
    if (!dropped) { dropped = true; await route.fetch(); await route.abort("failed"); }
    else await route.continue();
  });
  await page.getByRole("button", { name: "Increase", exact: true }).click();
  await count(14);
  await idle();
  await connected();
  await count(14);
  await page.unroute("**/_live/*/event");

  // Lose both deliveries of a form result, including a truncated HTTP body.
  // Reconnect caches the normalized value while the input is still protected;
  // the retained-ID acknowledgement must then release and reconcile it.
  await page.locator("#name").fill("  Alan  ");
  await page.evaluate(async () => {
    const { connectLiveViews } = await import("/_live/assets/esw-live.js");
    connectLiveViews()[0].source.close();
  });
  let truncated = false;
  await page.route("**/_live/*/event", async route => {
    if (!truncated) {
      truncated = true;
      await route.fetch();
      await route.fulfill({ status: 200, contentType: "application/json", body: "{" });
    } else await route.continue();
  });
  await page.getByRole("button", { name: "Say hello", exact: true }).click();
  await idle();
  await connected();
  assert.equal(await page.locator("#name").inputValue(), "Alan");
  assert.equal(await page.locator("#greeting").textContent(), "Hello, Alan!");
  await page.unroute("**/_live/*/event");

  const recovery = await page.evaluate(async () => {
    const { connectLiveViews } = await import("/_live/assets/esw-live.js");
    const client = connectLiveViews()[0];
    return client.apply({ revision: client.revision + 2, baseRevision: client.revision + 1, render: { dynamics: {} } });
  });
  assert.equal(recovery, false);
  await connected();
  await count(14);
  await page.evaluate(async () => {
    const { connectLiveViews } = await import("/_live/assets/esw-live.js");
    const client = connectLiveViews()[0];
    client.push("unknown");
    client.push("increment");
    client.push("noop");
  });
  await idle();
  await connected();
  await count(15);
  await checkClientDOM(page);
  assert.deepEqual(errors, []);
  mkdirSync(new URL("./artifacts", import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL("./artifacts/live-demo.png", import.meta.url)), fullPage: true });
  assert.equal((await context.request.post(`${url}/invalidate`, { headers })).status(), 204);
  await eventually(async () => await root.getAttribute("data-esw-state") === "expired", "Revoked instance did not stop reconnecting");
  await page.getByRole("button", { name: "Increase", exact: true }).click();
  await idle();
  await count(15);
  console.log("PASS: reconnect, lost-response and truncated-body retries, form reconciliation, revision-gap recovery.");
  console.log("PASS: no-op/error completion, revoked stream stops reconnecting, expired events are rejected");
} catch (error) {
  console.error(serverLog);
  console.error({ errors, networkErrors: networkErrors.slice(-20), live: await page?.evaluate(() => ({
    state: document.querySelector("[data-esw-live]")?.dataset.eswState, errors: window.liveErrors,
  })).catch(() => null) });
  throw error;
} finally {
  await browser?.close();
  server.kill("SIGTERM");
  await Promise.race([new Promise(resolve => server.once("exit", resolve)), delay(3000)]);
  if (server.exitCode == null) server.kill("SIGKILL");
}
