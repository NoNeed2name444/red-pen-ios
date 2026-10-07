import {validateExternal, validateExternalSchema} from "./main.js";

// Checks only the caller's item-level attestation, never its legal truth.
export function eligibleManifest(item) {
  const license = item?.license;
  return typeof item?.manifest_id === "string" && !!item.manifest_id.trim() &&
    typeof item.item_id === "string" && !!item.item_id.trim() &&
    Array.isArray(item.exclusion_flags) && !item.exclusion_flags.length &&
    license?.verified === true && license.scope === "item" && license.item_id === item.item_id &&
    typeof license.id === "string" && /^(?:unrestricted|CC-BY(?:-(?:1\.0|2\.0|2\.5|3\.0|4\.0))?)$/.test(license.id) &&
    Array.isArray(license.evidence) && !!license.evidence.length &&
    license.evidence.every(evidence => evidence?.item_id === item.item_id &&
      typeof evidence.url === "string" && !!evidence.url.trim() &&
      typeof evidence.terms === "string" && !!evidence.terms.trim());
}

export function mountAnnotations(document) {
  const ui = Object.fromEntries(["manifest", "schema", "item", "labels", "save", "export", "status"].map(id => [id, document.getElementById(id)]));
  let records = [], schema = null, annotations = new Map(), storageKey = "", storageWarning = "";
  let manifestRevision = 0, schemaRevision = 0;
  const memory = new Map();
  const persistenceWarnings = new Map();
  const stable = value => Array.isArray(value) ? value.map(stable) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
  const report = message => { ui.status.textContent = message + storageWarning; };
  const show = () => { ui.labels.value = JSON.stringify(annotations.get(ui.item.value)?.labels ?? {}, null, 2); };
  const validateAnnotation = item => {
    if (!item || Object.keys(item).sort().join(",") !== "labels,manifest_id" || !records.some(record => record.manifest_id === item.manifest_id)) throw Error("Unknown or malformed annotation");
    validateExternal(item.labels, schema);
  };
  function refresh() {
    ui.item.replaceChildren(...records.map(record => {
      const option = document.createElement("option");
      option.value = record.manifest_id;
      option.textContent = `${record.item_id} (${record.manifest_id})`;
      return option;
    }));
    storageKey = "provisional-annotations:" + JSON.stringify(stable({schema, ids: records.map(item => item.manifest_id).sort()}));
    annotations = new Map(memory.get(storageKey) ?? []);
    storageWarning = persistenceWarnings.get(storageKey) ?? "";
    // Session edits are authoritative even if persistent reads succeed while
    // writes fail (for example, browser storage quota exhaustion).
    if (memory.has(storageKey)) { show(); return; }
    try {
      const saved = JSON.parse(document.defaultView.localStorage.getItem(storageKey) || "[]");
      if (!Array.isArray(saved)) throw Error("Malformed stored annotations");
      const restored = new Map();
      for (const item of saved) {
        validateAnnotation(item);
        if (restored.has(item.manifest_id)) throw Error("Duplicate stored annotation");
        restored.set(item.manifest_id, item);
      }
      annotations = restored;
      memory.set(storageKey, [...restored]);
    } catch {
      storageWarning = " Browser persistence unavailable or invalid; session memory only.";
      persistenceWarnings.set(storageKey, storageWarning);
    }
    show();
  }
  ui.manifest.onchange = async () => {
    const revision = ++manifestRevision;
    const file = ui.manifest.files[0];
    if (!file) return;
    try {
      const input = (await file.text()).split(/\r?\n/).filter(line => line.trim()).map(line => JSON.parse(line));
      if (revision !== manifestRevision) return;
      if (input.some(item => !item || typeof item.manifest_id !== "string" || !item.manifest_id.trim() || !Array.isArray(item.exclusion_flags))) throw Error("Malformed manifest");
      if (new Set(input.map(item => item.manifest_id)).size !== input.length) throw Error("Duplicate manifest IDs");
      records = input.filter(eligibleManifest);
      refresh(); report(`Loaded ${records.length} eligible items.`);
    } catch (error) {
      if (revision !== manifestRevision) return;
      records = []; annotations = new Map(); ui.item.replaceChildren(); ui.labels.value = "";
      report(error.message);
    }
  };
  ui.schema.onchange = async () => {
    const revision = ++schemaRevision;
    const file = ui.schema.files[0];
    if (!file) return;
    try {
      const candidate = JSON.parse(await file.text());
      if (revision !== schemaRevision) return;
      validateExternalSchema(candidate); schema = candidate;
      refresh(); report("Caller schema loaded.");
    } catch (error) {
      if (revision !== schemaRevision) return;
      schema = null; annotations = new Map(); report(error.message);
    }
  };
  ui.item.onchange = show;
  ui.save.onclick = () => {
    try {
      if (!schema || !records.some(item => item.manifest_id === ui.item.value)) throw Error("Import a manifest and caller schema first");
      const item = {manifest_id: ui.item.value, labels: JSON.parse(ui.labels.value)};
      validateAnnotation(item);
      annotations.set(item.manifest_id, item); memory.set(storageKey, [...annotations]);
      try {
        document.defaultView.localStorage.setItem(storageKey, JSON.stringify([...annotations.values()]));
        storageWarning = ""; persistenceWarnings.delete(storageKey); report("Saved locally.");
      } catch {
        storageWarning = " Browser persistence unavailable; session memory only.";
        persistenceWarnings.set(storageKey, storageWarning);
        report("Saved for this session.");
      }
    } catch (error) { report(error.message); }
  };
  ui.export.onclick = () => {
    try {
      validateExternalSchema(schema);
      const values = [...annotations.values()]; values.forEach(validateAnnotation);
      const url = URL.createObjectURL(new Blob([values.map(item => JSON.stringify(item)).join("\n") + (values.length ? "\n" : "")], {type: "application/x-ndjson"}));
      const link = document.createElement("a"); link.href = url; link.download = "annotations.jsonl"; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) { report(error.message); }
  };
}

if (typeof document !== "undefined" && document.getElementById("manifest")) mountAnnotations(document);
