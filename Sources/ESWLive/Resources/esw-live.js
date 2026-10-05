import { Idiomorph } from "./idiomorph.js";
import { applyRenderPatch, renderHTML } from "./live-render.js";

const clients = new WeakMap();

/** One live root, one ordered event queue, and one revisioned render cache. */
export class LiveClient {
  constructor(root) {
    this.root = root;
    this.revision = null;
    this.statics = null;
    this.dynamics = [];
    this.keyed = Object.create(null);
    this.queue = [];
    this.dirty = new WeakMap();
    this.editVersion = 0;
    this.timers = new Map();
    this.disposed = false;
    this.sending = false;
    this.pending = null;
    this.streamURL = this.localURL(root.dataset.eswStream);
    this.eventURL = this.localURL(root.dataset.eswEvent);
    this.handlers = {
      click: event => this.click(event),
      input: event => this.input(event),
      change: event => this.input(event),
      submit: event => this.submit(event),
      reset: event => {
        if (event.target instanceof HTMLFormElement && event.target.closest("[data-esw-live]") === this.root) {
          event.preventDefault();
          this.resetForm(event.target);
        }
      },
    };
    for (const [name, handler] of Object.entries(this.handlers)) root.addEventListener(name, handler);
    this.offline = () => {
      if (this.expired) return;
      this.source?.close(); clearTimeout(this.retryTimer); this.status("disconnected");
    };
    this.online = () => this.resync();
    window.addEventListener("offline", this.offline);
    window.addEventListener("online", this.online);
    this.connect();
  }

  localURL(value) {
    const url = new URL(value, location.href);
    if (url.origin !== location.origin) throw new Error("Live endpoints must be same-origin");
    return url.href;
  }

  status(value) {
    if (value === "expired") {
      this.expired = true;
      this.source?.close();
      this.request?.abort();
      clearTimeout(this.retryTimer);
      for (const timer of this.timers.values()) clearTimeout(timer);
      this.timers.clear();
      this.queue.length = 0;
      this.pending = null;
      this.root.setAttribute("aria-busy", "false");
    }
    this.root.dataset.eswState = value;
    this.root.dispatchEvent(new CustomEvent("esw:status", { detail: { state: value } }));
  }

  connect() {
    if (this.disposed || this.expired) return;
    clearTimeout(this.retryTimer);
    this.source?.close();
    if (!navigator.onLine) { this.status("disconnected"); return; }
    this.status("connecting");
    const source = new EventSource(this.streamURL);
    this.source = source;
    source.addEventListener("update", event => {
      if (source !== this.source || this.disposed || this.expired) return;
      try {
        if (this.apply(JSON.parse(event.data))) {
          this.resyncDelay = 250;
          this.status("connected");
          this.drain();
        }
      } catch (error) { this.fail(error); this.resync(); }
    });
    source.onerror = () => {
      if (source === this.source && !this.disposed && !this.expired) {
        this.status(source.readyState === EventSource.CLOSED ? "expired" : "disconnected");
      }
    };
  }

  resync() {
    if (this.disposed || this.expired) return;
    this.source?.close();
    this.status("resyncing");
    clearTimeout(this.retryTimer);
    this.resyncDelay = Math.min((this.resyncDelay ?? 125) * 2, 5000);
    this.retryTimer = setTimeout(() => this.connect(), this.resyncDelay);
  }

  apply(update) {
    if (!Number.isSafeInteger(update.revision) || update.revision < 0 || !update.render) throw new Error("Invalid live update");
    const snapshot = update.baseRevision == null;
    const acknowledged = this.pending && this.pending.event.id === update.eventID
      ? this.acknowledge(this.pending) : false;
    if (this.revision != null && update.revision <= this.revision) {
      // A reconnect may have already cached the result while protecting dirty
      // fields. Reconcile that CURRENT render when its acknowledgement arrives.
      if (acknowledged) this.morph(this.statics, this.dynamics);
      return true;
    }
    if (!snapshot && update.baseRevision !== this.revision) { this.resync(); return false; }
    const patch = update.render;
    const { statics, dynamics, keyed } = applyRenderPatch(this, patch);
    if (acknowledged || patch.statics || Object.keys(patch.dynamics ?? {}).length || Object.keys(patch.keyed ?? {}).length) this.morph(statics, dynamics, keyed);
    this.statics = statics;
    this.dynamics = dynamics;
    this.keyed = keyed;
    this.revision = update.revision;
    this.root.dataset.eswRevision = String(this.revision);
    this.root.dispatchEvent(new CustomEvent("esw:update", { detail: update }));
    return true;
  }

  morph(statics, dynamics, keyed = this.keyed) {
    const html = renderHTML({ statics, dynamics, keyed });
    Idiomorph.morph(this.root, html, {
      morphStyle: "innerHTML", restoreFocus: true, ignoreActiveValue: false,
      callbacks: {
        beforeNodeMorphed: (oldNode, newNode) => {
          if (oldNode instanceof Element && oldNode.hasAttribute("esw-ignore")) return false;
          if (this.dirty.has(oldNode) && "value" in oldNode) {
            if (oldNode instanceof HTMLInputElement && oldNode.type === "file") return false;
            newNode.value = oldNode.value;
            if (oldNode instanceof HTMLInputElement) {
              newNode.setAttribute("value", oldNode.value);
              newNode.checked = oldNode.checked;
              newNode.toggleAttribute("checked", oldNode.checked);
            } else if (oldNode instanceof HTMLTextAreaElement) newNode.textContent = oldNode.value;
            else if (oldNode instanceof HTMLSelectElement) {
              for (const option of newNode.options) {
                const selected = [...oldNode.selectedOptions].some(old => old.value === option.value);
                option.selected = selected;
                option.toggleAttribute("selected", selected);
              }
            }
          }
          return true;
        },
      },
    });
  }

  acknowledge(item) {
    let changed = false;
    for (const [element, version] of item.edits) {
      if (this.dirty.get(element) === version) { this.dirty.delete(element); changed = true; }
    }
    return changed;
  }

  binding(target, attribute) {
    const element = target instanceof Element ? target.closest(`[${attribute}]`) : null;
    return element && this.root.contains(element) && element.closest("[data-esw-live]") === this.root ? element : null;
  }

  click(event) {
    const element = this.binding(event.target, "esw-click");
    if (!element || element.disabled || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    const values = Object.create(null);
    for (const attribute of element.attributes) {
      if (attribute.name.startsWith("esw-value-")) values[attribute.name.slice(10)] = [attribute.value];
    }
    this.push(element.getAttribute("esw-click"), values);
  }

  input(event) {
    const target = event.target;
    if (!(target instanceof Element) || target.closest("[data-esw-live]") !== this.root) return;
    this.dirty.set(target, ++this.editVersion);
    const element = this.binding(target, "esw-change");
    if (!element) return;
    clearTimeout(this.timers.get(element));
    const parsed = Number(element.getAttribute("esw-debounce") ?? 150);
    const delay = Number.isFinite(parsed) ? Math.max(0, Math.min(5000, parsed)) : 150;
    this.timers.set(element, setTimeout(() => {
      this.timers.delete(element);
      this.formEvent(element, element.getAttribute("esw-change"));
    }, delay));
  }

  submit(event) {
    const form = this.binding(event.target, "esw-submit");
    if (!(form instanceof HTMLFormElement)) return;
    event.preventDefault();
    clearTimeout(this.timers.get(form));
    this.timers.delete(form);
    this.formEvent(form, form.getAttribute("esw-submit"), event.submitter);
  }

  formEvent(element, name, submitter) {
    const form = element instanceof HTMLFormElement ? element : element.form;
    const values = Object.create(null);
    // A legitimate field named "elements" can shadow form.elements.
    const fields = form ? this.fields(form) : [element];
    const data = form ? new FormData(form, submitter) : [[element.name, element.value]];
    for (const [key, value] of data) {
      if (typeof value !== "string") { this.fail(new Error("Live file uploads are not supported")); return; }
      (values[key] ??= []).push(value);
    }
    const edits = fields.filter(field => this.dirty.has(field)).map(field => [field, this.dirty.get(field)]);
    this.push(name, values, edits);
  }

  fields(form) {
    return [...Object.getOwnPropertyDescriptor(HTMLFormElement.prototype, "elements").get.call(form)];
  }

  /** Discard unsubmitted edits and restore the latest committed server values. */
  resetForm(form) {
    if (form.closest("[data-esw-live]") !== this.root) return;
    for (const element of [form, ...this.fields(form)]) {
      this.dirty.delete(element);
      clearTimeout(this.timers.get(element));
      this.timers.delete(element);
    }
    if (this.statics) this.morph(this.statics, this.dynamics);
  }

  push(name, values = {}, edits = []) {
    if (this.disposed || this.expired || this.queue.length >= 64) { this.fail(new Error("Live event queue is full or closed; expired views require a reload")); return; }
    this.queue.push({ event: { id: crypto.randomUUID(), name, values }, edits });
    this.root.setAttribute("aria-busy", "true");
    this.drain();
  }

  async drain() {
    if (this.sending || this.disposed || this.root.dataset.eswState !== "connected") return;
    this.sending = true;
    try {
      while (this.queue.length && !this.disposed && this.root.dataset.eswState === "connected") {
        const item = this.queue[0];
        this.pending = item;
        item.event.baseRevision ??= this.revision;
        let response, reply;
        try {
          this.request = new AbortController();
          response = await fetch(this.eventURL, {
            method: "POST", credentials: "same-origin",
            signal: this.request.signal,
            headers: { "Content-Type": "application/json", "X-CSRF-Token": this.root.dataset.eswCsrf },
            body: JSON.stringify(item.event),
          });
          try { reply = await response.json(); }
          catch (error) {
            if (response.ok) throw error;
            // Middleware may return an HTML error before the adapter runs.
            reply = { error: `Live event failed (${response.status})` };
          }
        } catch (error) {
          if (this.disposed || this.expired) break;
          // Keep the same event ID: the server may already have committed it.
          this.fail(error);
          this.status("retrying");
          clearTimeout(this.retryTimer);
          this.retryTimer = setTimeout(() => this.resync(), 1000);
          break;
        }
        if (this.disposed || this.expired) break;
        if (response.ok) {
          try { if (!this.apply(reply)) break; }
          catch (error) { this.fail(error); this.resync(); break; }
        } else {
          this.fail(new Error(reply.error ?? `Live event failed (${response.status})`));
          if (response.status === 401 || response.status === 403 || response.status === 404) {
            this.source?.close();
            this.status("expired");
          } else this.resync(); // Rejected handlers may have consumed a revision.
        }
        this.queue.shift();
        this.pending = null;
      }
    } finally {
      this.sending = false;
      this.root.setAttribute("aria-busy", String(this.queue.length > 0));
    }
  }

  fail(error) { this.root.dispatchEvent(new CustomEvent("esw:error", { detail: { message: error.message } })); }

  dispose() {
    this.disposed = true;
    this.source?.close();
    this.request?.abort();
    clearTimeout(this.retryTimer);
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.timers.clear();
    for (const [name, handler] of Object.entries(this.handlers)) this.root.removeEventListener(name, handler);
    window.removeEventListener("offline", this.offline);
    window.removeEventListener("online", this.online);
    this.queue.length = 0;
    this.status("closed");
  }
}

export function connectLiveViews(scope = document) {
  return [...scope.querySelectorAll("[data-esw-live]")].map(root => {
    if (!clients.has(root) || clients.get(root).disposed) clients.set(root, new LiveClient(root));
    return clients.get(root);
  });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => connectLiveViews(), { once: true });
else connectLiveViews();
window.addEventListener("pagehide", () => {
  for (const root of document.querySelectorAll("[data-esw-live]")) clients.get(root)?.dispose();
});
window.addEventListener("pageshow", event => { if (event.persisted) connectLiveViews(); });
