import "./design-system.js";

export function createState(routes = []) {
  if (!Array.isArray(routes) || routes.some(route => typeof route !== "string" || !route) || new Set(routes).size !== routes.length) throw Error("Invalid caller routes");
  let revision = 0;
  let current = {route: null, status: "idle", data: null, error: null};
  const listeners = new Set();
  const publish = () => { for (const listener of listeners) listener(structuredClone(current)); };
  return {
    snapshot: () => structuredClone(current),
    subscribe(listener) {
      if (typeof listener !== "function") throw Error("State listener required");
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    navigate(route) {
      if (!routes.includes(route)) throw Error("Unknown caller route");
      revision += 1;
      current = {route, status: "idle", data: null, error: null};
      publish();
    },
    begin() { revision += 1; current = {...current, status: "loading", error: null}; const token = revision; publish(); return token; },
    complete(token, result) {
      if (token !== revision) return false;
      current = structuredClone({...current, status: result.status, data: result.data ?? null, error: result.error ?? null});
      publish();
      return true;
    },
  };
}

export function createApi(transport = null) {
  return {
    async call(operation, payload) {
      if (typeof transport !== "function") return {status: "unresolved", reason: "transport_missing"};
      return transport({operation, payload});
    },
  };
}

export function createRecords({transport = null, operations = null, idField = null} = {}) {
  const configured = typeof transport === "function" && operations && typeof operations.get === "string" && operations.get && typeof operations.list === "string" && operations.list && typeof idField === "string" && idField;
  const api = createApi(transport);
  const validate = records => {
    if (!Array.isArray(records)) throw Error("Record list required");
    const ids = records.map(record => record?.[idField]);
    if (ids.some(id => typeof id !== "string" || !id) || new Set(ids).size !== ids.length) throw Error("Missing or duplicate caller record IDs");
    return structuredClone(records);
  };
  return {
    async list() {
      if (!configured) return {status: "unresolved", reason: "record_access_config_missing"};
      const result = await api.call(operations.list, {});
      if (result.status === "unresolved") return result;
      return {status: "external_result", data: validate(result.data)};
    },
    async get(id) {
      if (!configured) return {status: "unresolved", reason: "record_access_config_missing"};
      if (typeof id !== "string" || !id) throw Error("Caller record ID required");
      const result = await api.call(operations.get, {id});
      if (result.status === "unresolved") return result;
      const [record] = validate([result.data]);
      if (record[idField] !== id) throw Error("Response record ID mismatch");
      return {status: "external_result", data: record};
    },
  };
}

function probability(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) throw Error("Finite caller probability in [0,1] required");
  return value;
}

export function bktUpdate(parameters, correct) {
  if (!parameters || typeof correct !== "boolean") throw Error("BKT parameters and boolean observation required");
  const {prior, learn, guess, slip} = parameters;
  [prior, learn, guess, slip].forEach(probability);
  const numerator = prior * (correct ? 1 - slip : slip);
  const denominator = numerator + (1 - prior) * (correct ? guess : 1 - guess);
  if (denominator === 0 || !Number.isFinite(denominator)) throw Error("Impossible observation: zero denominator");
  const posterior = numerator / denominator;
  return {posterior, nextPrior: posterior + (1 - posterior) * learn};
}

export function createBKT(parameters = null, saved = null) {
  if (!parameters || typeof parameters !== "object" || Array.isArray(parameters) || !Object.keys(parameters).length) return {
    observe: () => ({status: "unresolved", reason: "skill_parameters_missing"}),
    snapshot: () => ({status: "unresolved", reason: "skill_parameters_missing"}),
  };
  const configuration = structuredClone(parameters);
  const priors = new Map();
  const events = new Map();
  for (const [skillId, values] of Object.entries(configuration)) {
    if (!skillId || !values || Object.keys(values).sort().join(",") !== "guess,learn,prior,slip") throw Error("Caller skill ID and exact BKT parameters required");
    Object.values(values).forEach(probability);
    priors.set(skillId, values.prior);
  }
  const tracker = {
    observe(event) {
      if (!event || Object.keys(event).sort().join(",") !== "correct,id,skillId" || typeof event.id !== "string" || !event.id || !priors.has(event.skillId) || typeof event.correct !== "boolean") throw Error("Caller event ID, skill ID and boolean observation required");
      if (events.has(event.id)) {
        const previous = events.get(event.id);
        if (previous.skillId !== event.skillId || previous.correct !== event.correct) throw Error("Conflicting duplicate event ID");
        return {status: "duplicate", prior: priors.get(event.skillId)};
      }
      const result = bktUpdate({...configuration[event.skillId], prior: priors.get(event.skillId)}, event.correct);
      priors.set(event.skillId, result.nextPrior);
      events.set(event.id, structuredClone(event));
      return {status: "updated", ...result};
    },
    snapshot: () => ({version: 1, parameters: structuredClone(configuration), events: structuredClone([...events.values()]), priors: Object.fromEntries(priors)}),
  };
  if (saved) {
    if (saved.version !== 1 || !Array.isArray(saved.events)) throw Error("Unsupported BKT replay state");
    const canonicalParameters = values => JSON.stringify(Object.entries(values).sort().map(([id, value]) => [id, [value.prior, value.learn, value.guess, value.slip]]));
    if (!saved.parameters || canonicalParameters(saved.parameters) !== canonicalParameters(configuration)) throw Error("Replay parameter configuration mismatch");
    for (const event of saved.events) tracker.observe(event);
    const actual = tracker.snapshot().priors;
    if (!saved.priors || Object.keys(saved.priors).length !== Object.keys(actual).length || Object.entries(actual).some(([id, value]) => saved.priors[id] !== value)) throw Error("Replay prior mismatch");
  }
  return tracker;
}

export function validateExternal(value, schema) {
  const supported = ["type", "properties", "required", "additionalProperties", "items", "enum"];
  if (!schema || typeof schema !== "object" || Array.isArray(schema) || !Object.keys(schema).length || Object.keys(schema).some(key => !supported.includes(key))) throw Error("Caller schema required; unsupported keyword");
  const types = {object: value !== null && typeof value === "object" && !Array.isArray(value), array: Array.isArray(value), string: typeof value === "string", number: typeof value === "number" && Number.isFinite(value), integer: Number.isInteger(value), boolean: typeof value === "boolean", null: value === null};
  if (!types[schema.type]) throw Error("Caller schema type mismatch");
  const stable = item => Array.isArray(item) ? item.map(stable) : item && typeof item === "object" ? Object.fromEntries(Object.keys(item).sort().map(key => [key, stable(item[key])])) : item;
  if ("enum" in schema && (!Array.isArray(schema.enum) || !schema.enum.length || !schema.enum.some(item => JSON.stringify(stable(item)) === JSON.stringify(stable(value))))) throw Error("Caller enum mismatch");
  if (schema.type === "object") {
    const properties = schema.properties ?? {}, required = schema.required ?? [], extra = schema.additionalProperties ?? true;
    if (!properties || typeof properties !== "object" || Array.isArray(properties) || !Array.isArray(required) || required.some(key => typeof key !== "string") || typeof extra !== "boolean") throw Error("Malformed caller object schema");
    if (required.some(key => !Object.hasOwn(value, key))) throw Error("Caller required field missing");
    if (!extra && Object.keys(value).some(key => !Object.hasOwn(properties, key))) throw Error("Unexpected external fields");
    for (const [key, child] of Object.entries(properties)) { validateExternalSchema(child); if (Object.hasOwn(value, key)) validateExternal(value[key], child); }
  }
  if (schema.type === "array") { validateExternalSchema(schema.items); value.forEach(item => validateExternal(item, schema.items)); }
}

export function validateExternalSchema(schema) {
  const examples = {object: {}, array: [], string: "", number: 0, integer: 0, boolean: false, null: null};
  if (!schema || !Object.hasOwn(examples, schema.type)) throw Error("Explicit caller schema required");
  if ("enum" in schema && (!Array.isArray(schema.enum) || !schema.enum.length)) throw Error("Malformed enum");
  if ("required" in schema && (!Array.isArray(schema.required) || schema.required.some(key => typeof key !== "string"))) throw Error("Malformed required fields");
  const probe = {...schema}; delete probe.enum; delete probe.required;
  validateExternal(examples[schema.type], probe);
}

export async function classifyIntent(input, {classifier = null, classes = null, schema = null, classField = null} = {}) {
  if (typeof classifier !== "function" || !Array.isArray(classes) || !classes.length || !schema || typeof classField !== "string" || !classField) return {status: "unresolved", reason: "external_intent_config_missing"};
  if (classes.some(value => typeof value !== "string" || !value) || new Set(classes).size !== classes.length) throw Error("Caller intent classes required");
  if (typeof input !== "string" || !input.trim()) throw Error("Caller input text required");
  validateExternalSchema(schema);
  const result = await classifier(input, structuredClone(classes));
  validateExternal(result, schema);
  if (!classes.includes(result[classField])) throw Error("External intent outside caller classes");
  return {status: "external_result", data: structuredClone(result)};
}

export function renderEvidence(container, evidence) {
  if (!container || !evidence || typeof evidence.claim !== "string" || !Array.isArray(evidence.source_ids) || !Array.isArray(evidence.provenance)) throw Error("Caller evidence package required");
  const sources = new Map();
  for (const source of evidence.provenance) {
    if (typeof source.source_id !== "string" || !source.source_id || sources.has(source.source_id)) throw Error("Missing or duplicate citation source ID");
    sources.set(source.source_id, source);
  }
  if (new Set(evidence.source_ids).size !== evidence.source_ids.length || evidence.source_ids.some(id => !sources.has(id))) throw Error("Unknown or duplicate exact citation references");
  const missingLayers = ["L0", "L1", "L2", "L3"].some(layer => !evidence.layers?.[layer] || evidence.layers[layer].status === "unresolved");
  const status = evidence.status === "unresolved" || !evidence.source_ids.length || missingLayers ? "unresolved" : "pending";
  const document = container.ownerDocument;
  const statusElement = document.createElement("p"); statusElement.textContent = status;
  const claimElement = document.createElement("pre"); claimElement.textContent = evidence.claim;
  const citations = document.createElement("ul");
  for (const id of evidence.source_ids) {
    const item = document.createElement("li");
    item.textContent = JSON.stringify(sources.get(id));
    item.setAttribute("data-source-id", id);
    citations.appendChild(item);
  }
  container.setAttribute("data-status", status);
  container.replaceChildren(statusElement, claimElement, citations);
  return {status, source_ids: [...evidence.source_ids]};
}

export async function generateMCQ(context, {generator = null, schema = null, fields = null} = {}) {
  if (typeof generator !== "function" || !schema || !fields) return {status: "unresolved", reason: "external_question_config_missing"};
  if (Object.keys(fields).sort().join(",") !== "choiceId,choices,correctIds" || Object.values(fields).some(value => typeof value !== "string" || !value) || fields.choices === fields.correctIds) throw Error("Caller question field mapping required");
  validateExternalSchema(schema);
  const question = await generator(structuredClone(context));
  validateExternal(question, schema);
  const choices = question[fields.choices], correct = question[fields.correctIds];
  if (!Array.isArray(choices) || choices.length < 2 || !Array.isArray(correct) || !correct.length) throw Error("External choices and correct-ID list required");
  const ids = choices.map(choice => choice?.[fields.choiceId]);
  if (ids.some(id => typeof id !== "string" || !id) || new Set(ids).size !== ids.length) throw Error("Missing or duplicate choice IDs");
  if (correct.some(id => typeof id !== "string" || !ids.includes(id)) || new Set(correct).size !== correct.length) throw Error("Unknown or duplicate correct choice IDs");
  return {status: "external_result", mechanical_validation: "passed", review: "pending", data: structuredClone(question)};
}

export function createController(state, api) {
  return {
    async load(operation, payload) {
      const token = state.begin();
      try {
        const result = await api.call(operation, payload);
        if (!result || typeof result.status !== "string") throw Error("Invalid external response");
        return state.complete(token, result);
      } catch {
        return state.complete(token, {status: "unresolved", error: "request_failed"});
      }
    },
  };
}

export function mountShell(root, {routes = [], transport = null, render = null} = {}) {
  if (!root || !Array.isArray(routes) || routes.some(route => !route || typeof route !== "object")) throw Error("Shell root and caller routes required");
  if (render !== null && typeof render !== "function") throw Error("Caller renderer must be a function");
  const state = createState(routes.map(route => route.id));
  const api = createApi(transport);
  const controller = createController(state, api);
  const navigation = root.querySelector("[data-routes]");
  const status = root.querySelector("[data-status]");
  const content = root.querySelector("[data-content]");
  if (!navigation || !status || !content) throw Error("Shell navigation, status and content elements required");
  const update = snapshot => {
    status.textContent = snapshot.status;
    if (render) render(content, snapshot);
    else content.textContent = snapshot.data === null ? "" : JSON.stringify(snapshot.data);
  };
  const unsubscribe = state.subscribe(update);
  const buttons = routes.map(route => {
    const button = root.ownerDocument.createElement("button");
    button.type = "button";
    button.textContent = route.label ?? route.id;
    button.onclick = () => state.navigate(route.id);
    return button;
  });
  navigation.replaceChildren(...buttons);
  update(state.snapshot());
  return {state, api, controller, destroy() { unsubscribe(); for (const button of buttons) button.onclick = null; }};
}

if (typeof document !== "undefined") {
  const root = document.querySelector("[data-shell]");
  if (root) mountShell(root);
}
