/** Apply a render patch without mutating the previous cache. */
export function applyRenderPatch(previous, patch) {
  const record = value => value !== null && typeof value === "object" && !Array.isArray(value);
  if (!record(patch)) throw new Error("Invalid live render");
  const statics = patch.statics ?? previous?.statics;
  if (!Array.isArray(statics) || !statics.length || !statics.every(x => typeof x === "string")) throw new Error("Missing live snapshot");
  const dynamics = patch.statics != null ? new Array(statics.length - 1) : [...previous.dynamics];
  const keyed = Object.assign(Object.create(null), patch.statics != null ? {} : previous.keyed);
  const indexFor = key => {
    const index = Number(key);
    if (!Number.isSafeInteger(index) || index < 0 || index >= dynamics.length || String(index) !== key) throw new Error("Invalid dynamic index");
    return index;
  };
  if (!record(patch.dynamics ?? {})) throw new Error("Invalid dynamic values");
  for (const [key, value] of Object.entries(patch.dynamics ?? {})) {
    const index = indexFor(key);
    if (typeof value !== "string") throw new Error("Invalid dynamic value");
    dynamics[index] = value;
    delete keyed[key];
  }
  if (!record(patch.keyed ?? {})) throw new Error("Invalid keyed values");
  for (const [slot, changes] of Object.entries(patch.keyed ?? {})) {
    if (dynamics[indexFor(slot)] !== "" || !record(changes) || !record(changes.entries)) throw new Error("Invalid keyed slot");
    const before = keyed[slot];
    const order = changes.order ?? before?.order;
    if (!Array.isArray(order) || !order.every(key => typeof key === "string") || new Set(order).size !== order.length) throw new Error("Invalid keyed order");
    const identities = new Set(order);
    const entries = Object.create(null);
    for (const key of Object.keys(changes.entries)) {
      if (!identities.has(key)) throw new Error("Unexpected keyed row");
    }
    for (const key of order) {
      const old = before?.entries[key];
      entries[key] = Object.hasOwn(changes.entries, key) ? applyRenderPatch(old, changes.entries[key]) : old;
      if (!entries[key]) throw new Error("Missing keyed row");
    }
    keyed[slot] = { order: [...order], entries };
  }
  if (Array.from(dynamics).some(value => typeof value !== "string")) throw new Error("Incomplete live snapshot");
  return { statics, dynamics, keyed };
}

/** Reconstruct HTML, including nested keyed comprehensions. */
export function renderHTML({ statics, dynamics, keyed }) {
  let html = statics[0];
  for (let index = 0; index < dynamics.length; index++) {
    const rows = keyed?.[String(index)];
    html += (rows ? rows.order.map(key => renderHTML(rows.entries[key])).join("") : dynamics[index]) + statics[index + 1];
  }
  return html;
}
