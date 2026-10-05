import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { applyRenderPatch, renderHTML } from "../Sources/ESWLive/Resources/live-render.js";
import { checkClientDOM } from "./client.mjs";

const fixture = fileURLToPath(new URL("../Fixtures/PluginConsumer", import.meta.url));
const output = execFileSync("swift", ["run", "--disable-sandbox", "App", "--keyed-wire"], {
  cwd: fixture, encoding: "utf8", maxBuffer: 8 * 1024 * 1024,
});
const wire = output.split("\n").find(line => line.startsWith("KEYED_WIRE:"));
assert(wire, "Swift fixture must produce real serialized patches");
const updates = JSON.parse(wire.slice("KEYED_WIRE:".length));
let cache;
for (const update of updates) {
  cache = applyRenderPatch(cache, update.render);
  assert.equal(renderHTML(cache), update.expectedHTML, `Swift / JS agreement at revision ${update.revision}`);
}
assert.deepEqual(Object.keys(updates[1].render.keyed["0"].entries), ["3"]);
assert.deepEqual(updates[2].render.keyed["0"].entries, {});
assert.equal(updates[3].render.keyed["0"].order, undefined);
assert.deepEqual(Object.keys(updates[3].render.keyed["0"].entries), ["2"]);
assert.deepEqual(updates[4].render.keyed["0"].entries, {});
assert.deepEqual(updates[5].render.keyed["0"].order, []);

const original = JSON.stringify(cache);
for (const keyed of [
  { "0": { order: ["1", "1"], entries: {} } },
  { "0": { order: ["missing"], entries: {} } },
  { "0": { order: ["1"], entries: { unexpected: {} } } },
  { "01": { order: [], entries: {} } },
  { "-1": { order: [], entries: {} } },
  { "0": { order: "bad", entries: {} } },
]) {
  assert.throws(() => applyRenderPatch(cache, { dynamics: {}, keyed }));
  assert.equal(JSON.stringify(cache), original, "Rejected patches must leave the cache intact");
}
const flat = applyRenderPatch(cache, { statics: ["<p>", "</p>"], dynamics: { "0": "Legacy" } });
assert.equal(renderHTML(flat), "<p>Legacy</p>");
assert.equal(Object.keys(flat.keyed).length, 0);
let nested = applyRenderPatch(null, {
  statics: ["<section>", "</section>"], dynamics: { "0": "" },
  keyed: { "0": { order: ["outer"], entries: { outer: updates[0].render } } },
});
for (const update of updates.slice(1)) {
  nested = applyRenderPatch(nested, { dynamics: {}, keyed: { "0": { entries: { outer: update.render } } } });
  assert.equal(renderHTML(nested), `<section>${update.expectedHTML}</section>`);
}
console.log("PASS: Swift / JS wire agreement, insert, reorder, edit, delete, empty, fallback/recovery, malformed patches, legacy reset");

const assets = new Map(["esw-live.js", "live-render.js", "idiomorph.js"].map(name => [
  `/_live/assets/${name}`, readFileSync(new URL(`../Sources/ESWLive/Resources/${name}`, import.meta.url)),
]));
const server = createServer((request, response) => {
  if (assets.has(request.url)) {
    response.writeHead(200, { "Content-Type": "text/javascript" }).end(assets.get(request.url));
  } else if (request.url === "/") {
    response.writeHead(200, { "Content-Type": "text/html" }).end("<!doctype html><html><body></body></html>");
  } else {
    response.writeHead(204).end();
  }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
let browser;
try {
  const systemChrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  browser = await chromium.launch({ headless: true, ...(existsSync(systemChrome) ? { executablePath: systemChrome } : {}) });
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await checkClientDOM(page);
  const result = await page.evaluate(async updates => {
    const { LiveClient } = await import("/_live/assets/esw-live.js");
    const root = document.createElement("div");
    root.dataset.eswLive = "";
    root.dataset.eswStream = "/_live/keyed/stream";
    root.dataset.eswEvent = "/_live/keyed/event";
    document.body.append(root);
    const client = new LiveClient(root);
    client.source.close();
    client.status("disconnected");
    client.apply(updates[0]);
    const row = root.querySelector("#row-1");
    const input = root.querySelector("#draft-1");
    input.focus();
    input.value = "local draft";
    input.setSelectionRange(2, 5);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    client.apply(updates[1]);
    client.apply(updates[2]);
    const reordered = [...root.querySelectorAll("li")].map(element => element.id);
    const preserved = [row === root.querySelector("#row-1"), input === root.querySelector("#draft-1"),
      document.activeElement === input, input.value, input.selectionStart, input.selectionEnd];
    client.apply(updates[3]);
    const escaped = root.querySelector("#row-2 span").textContent;
    client.apply(updates[4]);
    const deleted = !root.querySelector("#row-3");
    // A duplicate delivery is acknowledged without applying the patch twice.
    client.apply(updates[4]);
    client.apply(updates[5]);
    const emptied = root.querySelectorAll("li").length === 0;
    for (const update of updates.slice(6)) client.apply(update);
    const recovered = [...root.querySelectorAll("li span")].map(element => element.textContent);
    client.dispose();
    root.remove();
    return { reordered, preserved, escaped, deleted, emptied, recovered };
  }, updates);
  assert.deepEqual(result.reordered, ["row-2", "row-3", "row-1"]);
  assert.deepEqual(result.preserved, [true, true, true, "local draft", 2, 5]);
  assert.equal(result.escaped, "<Changed>");
  assert(result.deleted && result.emptied);
  assert.deepEqual(result.recovered, ["First", "Two"]);
  assert.deepEqual(errors, []);
  console.log("PASS: real browser keyed updates, row identity, focused draft/selection, escaped text, deletion, clear, retry, recovery");
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
