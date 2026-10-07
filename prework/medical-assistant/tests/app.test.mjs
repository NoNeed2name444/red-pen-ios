import test from "node:test";
import assert from "node:assert/strict";
import {createState, createApi, createController, createRecords, bktUpdate, createBKT, classifyIntent, renderEvidence, generateMCQ} from "../app/main.js";
import {eligibleManifest} from "../app/annotation.js";

test("caller routing, isolated state and absent transport", async () => {
  const state = createState(["synthetic-route"]);
  state.navigate("synthetic-route");
  const snapshot = state.snapshot(); snapshot.route = "modified";
  assert.equal(state.snapshot().route, "synthetic-route");
  assert.throws(() => state.navigate("unknown"));
  assert.equal((await createApi().call("synthetic", {})).status, "unresolved");
});

test("older asynchronous responses cannot replace newer state", async () => {
  let resolveOld;
  const state = createState(["synthetic-route"]);
  const api = createApi(({payload}) => payload === "old" ? new Promise(resolve => {resolveOld = resolve;}) : Promise.resolve({status: "external_result", data: "new"}));
  const controller = createController(state, api);
  const old = controller.load("synthetic", "old");
  assert.equal(await controller.load("synthetic", "new"), true);
  resolveOld({status: "external_result", data: "old"});
  assert.equal(await old, false);
  assert.equal(state.snapshot().data, "new");
});

test("state publishes isolated changes and unsubscribes", () => {
  const state = createState(["fixture"]), changes = [];
  const unsubscribe = state.subscribe(snapshot => { changes.push(snapshot.status); snapshot.data = "modified"; });
  state.navigate("fixture");
  const token = state.begin(), response = {status: "external_result", data: {fixture: "original"}};
  state.complete(token, response); response.data.fixture = "changed";
  assert.equal(state.snapshot().data.fixture, "original");
  assert.deepEqual(changes, ["idle", "loading", "external_result"]);
  unsubscribe(); state.begin(); assert.equal(changes.length, 3);
});

test("annotation eligibility rechecks exact caller item attestations", () => {
  const record = {manifest_id: "__proto__", item_id: "fixture", exclusion_flags: [], license: {id: "CC-BY-4.0", verified: true, scope: "item", item_id: "fixture", evidence: [{item_id: "fixture", url: "https://example.invalid/fixture", terms: "Synthetic attestation"}]}};
  assert.equal(eligibleManifest(record), true);
  for (const license of [null, {...record.license, id: "CC-BY-NC"}, {...record.license, scope: "source"}, {...record.license, item_id: "other"}, {...record.license, evidence: []}, {...record.license, evidence: [{item_id: "fixture", url: "", terms: "fixture"}]}]) assert.equal(eligibleManifest({...record, license}), false);
  assert.equal(eligibleManifest({...record, exclusion_flags: ["excluded"]}), false);
});

test("caller-configured record access is read-only and checks exact IDs", async () => {
  assert.equal((await createRecords().list()).status, "unresolved");
  const requests = [];
  const record = {synthetic_id: "fixture-id", value: "synthetic"};
  const client = createRecords({idField: "synthetic_id", operations: {get: "caller-read", list: "caller-list"}, transport: async request => {
    requests.push(request);
    return {status: "external_result", data: request.operation === "caller-list" ? [record] : record};
  }});
  assert.equal((await client.get("fixture-id")).data.synthetic_id, "fixture-id");
  const list = await client.list(); list.data[0].value = "modified";
  assert.equal(record.value, "synthetic");
  assert.deepEqual(requests[0], {operation: "caller-read", payload: {id: "fixture-id"}});
  assert.equal("write" in client, false);
  await assert.rejects(() => client.get("unknown"), /mismatch/);
});

test("BKT formula, boundary parameters and impossible observations", () => {
  const parameters = {prior: 0.2, learn: 0.1, guess: 0.25, slip: 0.1};
  const result = bktUpdate(parameters, true);
  assert.ok(Math.abs(result.posterior - (0.18 / 0.38)) < 1e-12);
  assert.ok(Math.abs(result.nextPrior - ((0.18 / 0.38) + (1 - 0.18 / 0.38) * 0.1)) < 1e-12);
  assert.equal(bktUpdate({prior: 1, learn: 0, guess: 0, slip: 0}, true).nextPrior, 1);
  assert.throws(() => bktUpdate({prior: 0, learn: 0, guess: 0, slip: 0}, true), /zero denominator/);
  for (const value of [true, NaN, Infinity, -0.1, 1.1]) assert.throws(() => bktUpdate({...parameters, prior: value}, false));
  assert.throws(() => bktUpdate(parameters, 1));
});

test("caller skill tracker deduplicates events and replays serialized state", () => {
  assert.equal(createBKT().observe({}).status, "unresolved");
  const parameters = {"synthetic-skill": {prior: 0.2, learn: 0.1, guess: 0.25, slip: 0.1}};
  const tracker = createBKT(parameters);
  const event = {id: "synthetic-event", skillId: "synthetic-skill", correct: true};
  tracker.observe(event);
  const before = tracker.snapshot();
  assert.equal(tracker.observe(event).status, "duplicate");
  assert.deepEqual(tracker.snapshot(), before);
  assert.throws(() => tracker.observe({...event, correct: false}), /Conflicting/);
  const restored = createBKT(parameters, JSON.parse(JSON.stringify(before)));
  assert.deepEqual(restored.snapshot(), before);
  assert.throws(() => createBKT(parameters, {...before, priors: {"synthetic-skill": 0}}), /mismatch/);
});

test("intent adapter requires external classes and schema without defaults", async () => {
  assert.equal((await classifyIntent("synthetic input")).status, "unresolved");
  const configuration = {classes: ["synthetic-class"], classField: "external_class", schema: {type: "object", required: ["external_class"], properties: {external_class: {type: "string"}}, additionalProperties: false}, classifier: async () => ({external_class: "synthetic-class"})};
  assert.equal((await classifyIntent("synthetic input", configuration)).data.external_class, "synthetic-class");
  await assert.rejects(() => classifyIntent("synthetic input", {...configuration, classifier: async () => ({external_class: "unknown"})}), /outside/);
  await assert.rejects(() => classifyIntent("synthetic input", {...configuration, schema: {type: "object", oneOf: []}}), /unsupported/);
});

test("evidence rendering uses literal text and exact sources without approval", () => {
  const createElement = tag => ({tag, textContent: "", children: [], attributes: {}, appendChild(child) {this.children.push(child);}, setAttribute(key, value) {this.attributes[key] = value;}, replaceChildren(...children) {this.children = children;}});
  const container = createElement("div"); container.ownerDocument = {createElement};
  const evidence = {claim: "<script>synthetic literal text</script>", source_ids: ["synthetic-source"], provenance: [{source_id: "synthetic-source", citation: "synthetic citation"}], status: "unresolved", layers: {}};
  assert.equal(renderEvidence(container, evidence).status, "unresolved");
  assert.equal(container.children[1].textContent, evidence.claim);
  assert.equal("innerHTML" in container.children[1], false);
  const before = container.children;
  assert.throws(() => renderEvidence(container, {...evidence, source_ids: ["unknown"]}), /Unknown/);
  assert.equal(container.children, before);
  const layers = Object.fromEntries(["L0", "L1", "L2", "L3"].map(layer => [layer, {status: "external_result"}]));
  assert.equal(renderEvidence(container, {...evidence, status: "claimed-approval", layers}).status, "pending");
});

test("MCQ external generation validates caller schema and choice references only", async () => {
  assert.equal((await generateMCQ({})).status, "unresolved");
  const question = {synthetic_prompt: "Synthetic fixture only", options: [{key: "synthetic-a"}, {key: "synthetic-b"}], answer_keys: ["synthetic-a"]};
  const schema = {type: "object", required: ["synthetic_prompt", "options", "answer_keys"], additionalProperties: false, properties: {synthetic_prompt: {type: "string"}, options: {type: "array", items: {type: "object", required: ["key"], properties: {key: {type: "string"}}, additionalProperties: false}}, answer_keys: {type: "array", items: {type: "string"}}}};
  const config = {schema, fields: {choices: "options", choiceId: "key", correctIds: "answer_keys"}, generator: async () => question};
  const result = await generateMCQ({}, config);
  assert.equal(result.mechanical_validation, "passed"); assert.equal(result.review, "pending");
  for (const invalid of [{...question, answer_keys: ["unknown"]}, {...question, options: [question.options[0], question.options[0]]}, {...question, answer_keys: []}]) await assert.rejects(() => generateMCQ({}, {...config, generator: async () => invalid}));
  await assert.rejects(() => generateMCQ({}, {...config, schema: {...schema, oneOf: []}}), /unsupported/);
});
