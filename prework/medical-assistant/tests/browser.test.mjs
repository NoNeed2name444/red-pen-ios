import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {createRequire} from "node:module";

// Install with npm ci and npx playwright install chromium. Optional
// PLAYWRIGHT_MODULE/CHROMIUM_PATH select existing tools. No provider requests occur.
const require = createRequire(import.meta.url);
let chromium;
try { ({chromium} = require(process.env.PLAYWRIGHT_MODULE || "playwright")); }
catch { throw Error("Browser tests require Playwright: run npm ci and npx playwright install chromium, or configure PLAYWRIGHT_MODULE/CHROMIUM_PATH."); }
const appDirectory = fileURLToPath(new URL("../app/", import.meta.url));
const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  if (!/^\/[a-z-]+\.(html|js)$/.test(path)) { response.writeHead(404).end(); return; }
  try {
    response.setHeader("content-type", path.endsWith(".js") ? "text/javascript" : "text/html");
    response.end(await readFile(appDirectory + path.slice(1)));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
let browser;
try {
  browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || undefined, headless: true, args: ["--no-sandbox"]});
} catch (error) { server.close(); throw error; }
const origin = `http://127.0.0.1:${server.address().port}`;
test.after(async () => { await browser.close(); await new Promise(resolve => server.close(resolve)); });

test("real browser shell shows caller routes, async state, literal data and navigation invalidation", async () => {
  const page = await browser.newPage({viewport: {width: 390, height: 844}});
  try {
    await page.goto(origin + "/index.html");
    await page.waitForFunction(() => document.querySelector("[data-status]").textContent === "idle");
    await page.evaluate(async () => {
      const {mountShell} = await import("/main.js");
      window.fixture = mountShell(document.querySelector("[data-shell]"), {
        routes: [{id: "fixture-a", label: "Synthetic A"}, {id: "fixture-b", label: "Synthetic B"}],
        transport: () => new Promise(resolve => { window.finishFixture = resolve; }),
      });
    });
    await page.getByRole("button", {name: "Synthetic A"}).click();
    await page.evaluate(() => { window.pendingFixture = window.fixture.controller.load("synthetic", {}); });
    assert.equal(await page.locator("[data-status]").textContent(), "loading");
    await page.evaluate(async () => { window.finishFixture({status: "external_result", data: "<img src=x onerror=window.executed=true>"}); await window.pendingFixture; });
    assert.equal(await page.locator("[data-status]").textContent(), "external_result");
    assert.match(await page.locator("[data-content]").textContent(), /<img/);
    assert.equal(await page.locator("[data-content] img").count(), 0);
    await page.evaluate(() => { window.pendingFixture = window.fixture.controller.load("synthetic", {}); });
    await page.getByRole("button", {name: "Synthetic B"}).click();
    await page.evaluate(async () => { window.finishFixture({status: "external_result", data: "stale"}); await window.pendingFixture; });
    assert.equal(await page.locator("[data-status]").textContent(), "idle");
    assert.equal(await page.locator("[data-content]").textContent(), "");
  } finally { await page.close(); }
});

const labelSchema = {type: "object", required: ["fixture"], properties: {fixture: {type: "string", enum: ["synthetic-label"]}}, additionalProperties: false};
const record = {manifest_id: "__proto__", item_id: "fixture", exclusion_flags: [], license: {id: "CC-BY-4.0", verified: true, scope: "item", item_id: "fixture", evidence: [{item_id: "fixture", url: "https://example.invalid/fixture", terms: "Synthetic test only"}]}};
const upload = (page, selector, name, data) => page.locator(selector).setInputFiles({name, mimeType: "application/json", buffer: Buffer.from(data)});
async function importFixtures(page) {
  await page.goto(origin + "/annotation.html");
  await upload(page, "#manifest", "manifest.jsonl", [record, {...record, manifest_id: "excluded", exclusion_flags: ["fixture"]}, {...record, manifest_id: "unverified", license: null}].map(item => JSON.stringify(item)).join("\r\n"));
  await page.waitForFunction(() => document.querySelector("#status").textContent.startsWith("Loaded 1 eligible items."));
  await upload(page, "#schema", "schema.json", JSON.stringify(labelSchema));
  await page.waitForFunction(() => document.querySelector("#status").textContent.startsWith("Caller schema loaded."));
}

test("real browser annotations save, restore and download exact JSONL; invalid labels fail", async () => {
  const page = await browser.newPage({acceptDownloads: true});
  try {
    await importFixtures(page);
    assert.equal(await page.locator("#item option").count(), 1);
    await page.locator("#labels").fill('{"fixture":"invalid"}');
    await page.locator("#save").click();
    assert.match(await page.locator("#status").textContent(), /enum/);
    await page.locator("#labels").fill('{"fixture":"synthetic-label"}');
    await page.locator("#save").click();
    assert.equal(await page.locator("#status").textContent(), "Saved locally.");
    const downloading = page.waitForEvent("download"); await page.locator("#export").click();
    const download = await downloading;
    assert.equal(download.suggestedFilename(), "annotations.jsonl");
    assert.deepEqual(JSON.parse((await readFile(await download.path(), "utf8")).trim()), {manifest_id: "__proto__", labels: {fixture: "synthetic-label"}});
    await importFixtures(page);
    assert.deepEqual(JSON.parse(await page.locator("#labels").inputValue()), {fixture: "synthetic-label"});
    await upload(page, "#schema", "schema.json", JSON.stringify({...labelSchema, oneOf: []}));
    await page.waitForFunction(() => document.querySelector("#status").textContent.includes("unsupported"));
    await page.locator("#save").click();
    assert.match(await page.locator("#status").textContent(), /Import a manifest/);
  } finally { await page.close(); }
});

test("real browser annotation session remains usable with denied or corrupt persistence", async () => {
  for (const denied of [true, false]) {
    const context = await browser.newContext({acceptDownloads: true});
    if (denied) await context.addInitScript(() => { Object.defineProperty(window, "localStorage", {get() { throw Error("Synthetic persistence denial"); }}); });
    const page = await context.newPage();
    try {
      await importFixtures(page);
      if (!denied) {
        await page.evaluate(() => { const key = "provisional-annotations:" + JSON.stringify({ids: ["__proto__"], schema: {additionalProperties: false, properties: {fixture: {enum: ["synthetic-label"], type: "string"}}, required: ["fixture"], type: "object"}}); localStorage.setItem(key, "{broken"); });
        await importFixtures(page);
        await page.waitForFunction(() => document.querySelector("#status").textContent.includes("invalid"));
      }
      assert.equal(await page.locator("#item option").count(), 1);
      await page.locator("#labels").fill('{"fixture":"synthetic-label"}'); await page.locator("#save").click();
      assert.match(await page.locator("#status").textContent(), denied ? /Saved for this session/ : /Saved locally/);
      const downloading = page.waitForEvent("download"); await page.locator("#export").click();
      assert.equal(JSON.parse((await readFile(await (await downloading).path(), "utf8")).trim()).manifest_id, "__proto__");
    } finally { await context.close(); }
  }
});

test("real browser quota failures preserve latest session labels when reads are null or stale", async () => {
  for (const stale of [false, true]) {
    const context = await browser.newContext({acceptDownloads: true});
    const page = await context.newPage();
    try {
      await importFixtures(page);
      const quotaSchema = structuredClone(labelSchema);
      quotaSchema.properties.fixture.enum.push("synthetic-latest");
      await upload(page, "#schema", "schema.json", JSON.stringify(quotaSchema));
      await page.waitForFunction(() => document.querySelector("#status").textContent.startsWith("Caller schema loaded."));
      if (stale) {
        await page.locator("#labels").fill('{"fixture":"synthetic-label"}'); await page.locator("#save").click();
      }
      await page.evaluate(() => { Storage.prototype.setItem = () => { throw new DOMException("Synthetic quota failure", "QuotaExceededError"); }; });
      await page.locator("#labels").fill('{"fixture":"synthetic-latest"}'); await page.locator("#save").click();
      assert.match(await page.locator("#status").textContent(), /session/);
      await upload(page, "#schema", "schema.json", JSON.stringify(quotaSchema));
      await page.waitForFunction(() => document.querySelector("#status").textContent.startsWith("Caller schema loaded."));
      assert.deepEqual(JSON.parse(await page.locator("#labels").inputValue()), {fixture: "synthetic-latest"});
      assert.match(await page.locator("#status").textContent(), /session memory only/);
      const downloading = page.waitForEvent("download"); await page.locator("#export").click();
      assert.deepEqual(JSON.parse((await readFile(await (await downloading).path(), "utf8")).trim()), {manifest_id: "__proto__", labels: {fixture: "synthetic-latest"}});
    } finally { await context.close(); }
  }
});

test("real browser evidence is literal and injected intent/MCQ/BKT adapters operate without defaults", async () => {
  const page = await browser.newPage();
  try {
    await page.goto(origin + "/index.html");
    const result = await page.evaluate(async () => {
      const {renderEvidence, classifyIntent, generateMCQ, createBKT} = await import("/main.js");
      const root = document.querySelector("[data-content]");
      const evidence = {claim: "<script>window.executed=true</script>", source_ids: ["fixture"], provenance: [{source_id: "fixture", citation: "Synthetic fixture"}], status: "pending", layers: Object.fromEntries(["L0", "L1", "L2", "L3"].map(layer => [layer, {status: "external_result"}]))};
      const rendered = renderEvidence(root, evidence);
      const intent = await classifyIntent("Synthetic", {classifier: async () => ({fixture: "synthetic"}), classes: ["synthetic"], classField: "fixture", schema: {type: "object", required: ["fixture"], properties: {fixture: {type: "string"}}, additionalProperties: false}});
      const question = await generateMCQ({}, {generator: async () => ({choices: [{id: "a"}, {id: "b"}], correct: ["a"]}), fields: {choices: "choices", choiceId: "id", correctIds: "correct"}, schema: {type: "object", required: ["choices", "correct"], properties: {choices: {type: "array", items: {type: "object", required: ["id"], properties: {id: {type: "string"}}}}, correct: {type: "array", items: {type: "string"}}}}});
      const parameters = {fixture: {prior: 0.2, learn: 0.1, guess: 0.25, slip: 0.1}}, tracker = createBKT(parameters);
      tracker.observe({id: "event", skillId: "fixture", correct: true});
      const saved = JSON.parse(JSON.stringify(tracker.snapshot()));
      return {rendered, literal: root.querySelector("pre").textContent, scripts: root.querySelectorAll("script").length, intent: intent.status, question: question.review, replay: JSON.stringify(createBKT(parameters, saved).snapshot()) === JSON.stringify(saved)};
    });
    assert.equal(result.rendered.status, "pending"); assert.equal(result.scripts, 0); assert.match(result.literal, /<script>/);
    assert.equal(result.intent, "external_result"); assert.equal(result.question, "pending"); assert.equal(result.replay, true);
  } finally { await page.close(); }
});
