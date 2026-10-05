import assert from "node:assert/strict";

// Small protocol/DOM cases run in the same real browser and use the actual
// bundled client and Idiomorph. The HTTP acceptance lives in live.mjs.
export async function checkClientDOM(page) {
  await page.route("**/_live/dom-probe/event", route => route.fulfill({ status: 403, contentType: "text/html", body: "<h1>Forbidden</h1>" }));
  const result = await page.evaluate(async () => {
    const { LiveClient } = await import("/_live/assets/esw-live.js");
    const root = document.createElement("div");
    root.dataset.eswLive = "";
    root.dataset.eswStream = "/_live/dom-probe/stream";
    root.dataset.eswEvent = "/_live/dom-probe/event";
    document.body.append(root);
    const client = new LiveClient(root);
    client.source.close();
    client.status("disconnected");
    const markup = `<form id="probe-form"><input id="probe-name" name="name" value="server"><textarea id="probe-notes" name="notes">saved</textarea><input id="probe-checked" name="checked" type="checkbox"><select id="probe-select" name="selection" multiple><option value="a" selected>A</option><option value="b">B</option></select><input name="elements" value="field"><button type="submit" name="action" value="save">Save</button></form><div id="probe-ignore" esw-ignore>initial</div>`;
    const snapshot = (revision, html) => ({ revision, render: { statics: [html], dynamics: {} } });
    client.apply(snapshot(1, markup));
    const field = id => root.querySelector(`#probe-${id}`);
    const input = field("name"), notes = field("notes"), checked = field("checked"), select = field("select");
    const edit = element => element.dispatchEvent(new Event("input", { bubbles: true }));
    input.value = "draft"; edit(input);
    notes.value = "local notes"; edit(notes);
    checked.checked = true; edit(checked);
    select.options[0].selected = false; select.options[1].selected = true; edit(select);
    field("ignore").textContent = "widget state";
    client.apply(snapshot(2, markup.replace("server", "normalized")));
    const preserved = [input.value, notes.value, checked.checked, [...select.selectedOptions].map(x => x.value), field("ignore").textContent];

    // A field called elements must not shadow serialization; retain submitter.
    const form = field("form");
    client.formEvent(form, "save", form.querySelector("button"));
    const serialized = client.queue.pop().event.values;

    // A late acknowledgement must not erase an edit made after submission.
    client.pending = { event: { id: "ack" }, edits: [[input, client.dirty.get(input)]] };
    input.value = "newer draft"; edit(input);
    client.apply({ revision: 2, eventID: "ack", render: { dynamics: {} } });
    const newer = input.value;
    client.pending = null;
    form.reset();
    const reset = [input.value, notes.value, checked.checked, [...select.selectedOptions].map(x => x.value)];
    const terminal = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("HTML authorization failure did not stop retries")), 2000);
      root.addEventListener("esw:status", event => {
        if (event.detail.state === "expired") { clearTimeout(timeout); resolve(); }
      });
    });
    client.status("connected");
    client.push("denied");
    await terminal;
    const expired = [root.dataset.eswState, client.queue.length, root.getAttribute("aria-busy")];
    client.dispose();
    root.remove();
    return { preserved, serialized, newer, reset, expired };
  });
  await page.unroute("**/_live/dom-probe/event");
  assert.deepEqual(result.preserved, ["draft", "local notes", true, ["b"], "widget state"]);
  assert.equal(result.serialized.action[0], "save");
  assert.equal(result.serialized.elements[0], "field");
  assert.equal(result.newer, "newer draft");
  assert.deepEqual(result.reset, ["normalized", "saved", false, ["a"]]);
  assert.deepEqual(result.expired, ["expired", 0, "false"]);
  console.log("PASS: checkbox/select/textarea drafts, ignored DOM, submitter, field-name collisions, newer edits, form reset");
}
