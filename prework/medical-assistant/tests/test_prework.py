"""Verify offline checks against isolated directories, without content or keys."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.prework import (
    DIRECTORIES,
    annotate,
    bounded_path,
    etl,
    evaluate_grounding,
    extract_triplets,
    graph_integrity,
    graph_plan,
    missing_directories,
    observe_negation,
    package_evidence,
    resolve_entity,
    validate_l0,
    validate_l1,
    validate_labels,
)


class ScaffoldCheckTests(unittest.TestCase):
    def test_missing_layout_does_not_create_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(missing_directories(root), list(DIRECTORIES))
            self.assertEqual(list(root.iterdir()), [])

    def test_complete_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in DIRECTORIES:
                (root / name).mkdir(parents=True)
            self.assertEqual(missing_directories(root), [])

    def test_regular_file_cannot_substitute_for_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "app").write_text("placeholder", encoding="utf-8")
            self.assertIn("app", missing_directories(root))


class ETLTests(unittest.TestCase):
    @staticmethod
    def record(identifier="synthetic-1", text="  SYNTHETIC\talpha!  "):
        return {
            "id": identifier,
            "source": "synthetic-fixture-only",
            "text": text,
            "license": {
                "id": "CC-BY-4.0",
                "item_id": identifier,
                "scope": "item",
                "verified": True,
                "evidence": [
                    {
                        "item_id": identifier,
                        "url": "https://example.invalid/synthetic-fixture",
                        "terms": "Synthetic test attestation; not real source evidence",
                    }
                ],
            },
        }

    def test_idempotence_and_changed_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "input.jsonl", root / "output"
            source.write_text(json.dumps(self.record()) + "\n")
            first = etl(source, output, root)
            before = {p: p.stat().st_mtime_ns for p in output.rglob("*") if p.is_file()}
            self.assertEqual(first, etl(source, output, root))
            self.assertEqual(before, {p: p.stat().st_mtime_ns for p in before})
            self.assertEqual(first[0]["text"], "SYNTHETIC alpha!")
            source.write_text(json.dumps(self.record(text="SYNTHETIC beta")) + "\n")
            self.assertNotEqual(
                first[0]["manifest_id"], etl(source, output, root)[0]["manifest_id"]
            )

    def test_resume_after_interruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "input.jsonl", root / "output"
            second = self.record("synthetic-2")
            second["text"] = 123
            source.write_text("\n".join(map(json.dumps, [self.record(), second])))
            with self.assertRaises(ValueError):
                etl(source, output, root)
            objects = list((output / "objects").glob("*.json"))
            self.assertEqual(len(objects), 1)
            previous = objects[0].stat().st_mtime_ns
            second["text"] = "SYNTHETIC resumed"
            source.write_text("\n".join(map(json.dumps, [self.record(), second])))
            self.assertEqual(len(etl(source, output, root)), 2)
            self.assertEqual(objects[0].stat().st_mtime_ns, previous)

    def test_unknown_nc_and_source_claims_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for license_id in ["unknown", "CC-BY-NC", "CC-BY-NC-SA", "CC-BY-SA"]:
                record = self.record()
                record["license"]["id"] = license_id
                source = root / "input.jsonl"
                source.write_text(json.dumps(record))
                result = etl(source, root / "out", root)[0]
                self.assertTrue(result["exclusion_flags"])
                self.assertNotIn("text", result)
            record = self.record()
            record["license"]["evidence"][0]["item_id"] = "some-other-item"
            source.write_text(json.dumps(record))
            self.assertTrue(etl(source, root / "out", root)[0]["exclusion_flags"])

    def test_path_boundaries_and_symlink_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            assets = root / "assets"
            assets.mkdir()
            (assets / "escape").symlink_to(root)
            for name in [
                "../outside.png",
                str(root / "outside.png"),
                "escape/file.png",
            ]:
                with self.assertRaises(ValueError):
                    bounded_path(assets, name)

    def test_corrupt_object_repaired(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "input.jsonl", root / "output"
            source.write_text(json.dumps(self.record()))
            expected = etl(source, output, root)
            artifact = output / "objects" / (expected[0]["manifest_id"] + ".json")
            artifact.write_text("corrupted")
            self.assertEqual(etl(source, output, root), expected)

    def test_changed_image_bytes_and_adapter_version_invalidate_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output, image = (
                root / "input.jsonl",
                root / "output",
                root / "image.bin",
            )
            record = self.record()
            record["image"] = image.name
            source.write_text(json.dumps(record))
            image.write_bytes(b"synthetic image one")
            calls = []

            def adapter(path):
                calls.append(path)
                return b"synthetic adapter output " + path.read_bytes()

            first = etl(source, output, root, adapter, "synthetic-v1")
            self.assertEqual(first, etl(source, output, root, adapter, "synthetic-v1"))
            self.assertEqual(len(calls), 1)
            image.write_bytes(b"synthetic image two")
            changed = etl(source, output, root, adapter, "synthetic-v1")
            self.assertEqual(len(calls), 2)
            self.assertNotEqual(first[0]["manifest_id"], changed[0]["manifest_id"])
            revised = etl(source, output, root, adapter, "synthetic-v2")
            self.assertEqual(len(calls), 3)
            self.assertNotEqual(changed[0]["manifest_id"], revised[0]["manifest_id"])
            record["license"]["id"] = "unknown"
            record["image"] = "../forbidden.bin"
            source.write_text(json.dumps(record))
            self.assertTrue(
                etl(source, output, root, adapter, "synthetic-v2")[0]["exclusion_flags"]
            )
            self.assertEqual(len(calls), 3)


class AnnotationTests(unittest.TestCase):
    schema = {
        "type": "object",
        "required": ["synthetic_tag"],
        "properties": {"synthetic_tag": {"type": "string", "enum": ["fixture"]}},
        "additionalProperties": False,
    }

    def test_missing_or_unsupported_schema_refused(self):
        for schema in [None, {}, {"type": "object", "oneOf": []}]:
            with self.assertRaises(ValueError):
                validate_labels({}, schema)

    def test_required_enum_and_unexpected_fields(self):
        for labels in [
            {},
            {"synthetic_tag": "wrong"},
            {"synthetic_tag": "fixture", "extra": True},
        ]:
            with self.assertRaises(ValueError):
                validate_labels(labels, self.schema)
        validate_labels({"synthetic_tag": "fixture"}, self.schema)

    def test_export_rejects_unknown_excluded_duplicate_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "annotations.jsonl"
            manifests = [
                {
                    **ETLTests.record(),
                    "item_id": "synthetic-1",
                    "manifest_id": "synthetic-id",
                    "exclusion_flags": [],
                }
            ]
            annotation = {
                "manifest_id": "synthetic-id",
                "labels": {"synthetic_tag": "fixture"},
            }
            annotate(manifests, [annotation], self.schema, output)
            expected = output.read_bytes()
            for annotations in [
                [annotation, annotation],
                [{**annotation, "manifest_id": "unknown"}],
                [{**annotation, "labels": {}}],
            ]:
                with self.assertRaises(ValueError):
                    annotate(manifests, annotations, self.schema, output)
                self.assertEqual(output.read_bytes(), expected)
            with self.assertRaises(ValueError):
                annotate(
                    [{**manifests[0], "exclusion_flags": ["unknown"]}],
                    [annotation],
                    self.schema,
                    output,
                )
            forged = {**manifests[0], "license": {"id": "unknown"}}
            with self.assertRaises(ValueError):
                annotate([forged], [annotation], self.schema, output)
            self.assertEqual(output.read_bytes(), expected)


class L0SchemaCheckTests(unittest.TestCase):
    schema = {
        "type": "object",
        "required": ["tag"],
        "properties": {"tag": {"type": "string", "enum": ["synthetic"]}},
    }

    def test_caller_schema_required_type_enum_and_unsupported(self):
        self.assertEqual(
            validate_l0({"tag": "synthetic"}, self.schema),
            {"status": "passed", "passed": True, "errors": []},
        )
        for record in [{}, {"tag": 3}, {"tag": "other"}]:
            result = validate_l0(record, self.schema)
            self.assertFalse(result["passed"])
            self.assertEqual(result["status"], "failed")
            self.assertTrue(result["errors"])
        self.assertEqual(
            validate_l0({"tag": "synthetic"}, {"type": "object", "oneOf": []})[
                "status"
            ],
            "failed",
        )

    def test_missing_schema_is_unresolved_and_cli_emits_structured_result(self):
        self.assertEqual(
            validate_l0({"tag": "synthetic"}),
            {
                "status": "unresolved",
                "passed": False,
                "errors": ["caller_schema_missing"],
            },
        )
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "record.json"
            record.write_text('{"tag":"synthetic"}', encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "scripts/prework.py", "l0", str(record)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)["status"], "unresolved")


class L1NumericCheckTests(unittest.TestCase):
    def test_finite_numbers_caller_bounds_bool_and_unit_match(self):
        rules = {"measure": {"min": 1, "max": 3, "unit": "cm"}}
        self.assertTrue(
            validate_l1({"measure": {"value": 2.5, "unit": "cm"}}, rules)["passed"]
        )
        for record in [
            {"measure": {"value": True, "unit": "cm"}},
            {"measure": {"value": float("nan"), "unit": "cm"}},
            {"measure": {"value": float("inf"), "unit": "cm"}},
            {"measure": {"value": 2, "unit": "mm"}},
            {"measure": {"value": 4, "unit": "cm"}},
            {},
        ]:
            self.assertFalse(validate_l1(record, rules)["passed"])

    def test_unitless_fields_and_malformed_or_missing_rules(self):
        self.assertTrue(validate_l1({"count": 2}, {"count": {"min": 2}})["passed"])
        self.assertFalse(validate_l1({"count": 2}, {})["passed"])
        self.assertFalse(
            validate_l1({"count": 2}, {"count": {"min": float("nan")}})["passed"]
        )
        self.assertFalse(
            validate_l1({"count": 2}, {"count": {"min": 3, "max": 1}})["passed"]
        )
        self.assertFalse(validate_l1({"count": 2}, {"count": {"min": True}})["passed"])

    def test_l1_cli_returns_structured_result_for_caller_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "record.json"
            rules = Path(directory) / "rules.json"
            record.write_text('{"count":2}', encoding="utf-8")
            rules.write_text('{"count":{"min":2}}', encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "scripts/prework.py", "l1", str(record), str(rules)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0)
            self.assertTrue(json.loads(result.stdout)["passed"])


class TripletTests(unittest.TestCase):
    def test_external_triplets_evidence_and_stable_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "input.jsonl"
            source.write_text(json.dumps(ETLTests.record()))
            manifests = etl(source, root / "etl", root)
            identifier = manifests[0]["manifest_id"]
            triple = {
                "head": "synthetic-head",
                "relation": "SYNTHETIC_RELATION",
                "tail": "synthetic-tail",
                "source_ids": [identifier],
            }
            output = root / "triplets.jsonl"
            first = extract_triplets(manifests, lambda item: [triple, triple], output)
            self.assertEqual(len(first), 1)
            self.assertEqual(
                first, extract_triplets(manifests, lambda item: [triple], output)
            )
            before = output.read_bytes()
            for invalid in [
                {**triple, "head": ""},
                {**triple, "source_ids": ["unknown"]},
                {**triple, "extra": True},
            ]:
                with self.assertRaises(ValueError):
                    extract_triplets(manifests, lambda item: [invalid], output)
                self.assertEqual(output.read_bytes(), before)
            manifests[0]["license"]["verified"] = False
            calls = []
            self.assertEqual(
                extract_triplets(manifests, lambda item: calls.append(item), output), []
            )
            self.assertEqual(calls, [])

    def test_no_extractor_or_terminology_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                extract_triplets([], None, Path(directory) / "triplets.jsonl")
        for system in ["UMLS", "SNOMED CT", "ICD11"]:
            self.assertEqual(
                resolve_entity("synthetic-term", system)["status"], "unresolved"
            )


class GraphTests(unittest.TestCase):
    nodes = [
        {"id": "synthetic-a", "kind": "Disease"},
        {"id": "synthetic-b", "kind": "Drug"},
    ]
    relationships = [
        {
            "id": "synthetic-r",
            "head": "synthetic-a",
            "tail": "synthetic-b",
            "type": "SYNTHETIC_RELATION",
        }
    ]
    vectors = [
        {"id": "synthetic-a", "values": [0.1, 0.2]},
        {"id": "synthetic-b", "values": [0.3, 0.4]},
    ]

    def test_missing_duplicate_dangling_and_mismatched_ids(self):
        self.assertEqual(
            graph_integrity(self.nodes, self.relationships, self.vectors), []
        )
        errors = graph_integrity(
            [*self.nodes, self.nodes[0], {}],
            [{**self.relationships[0], "tail": "unknown"}],
            self.vectors[:1],
        )
        self.assertIn("duplicate_id:node:synthetic-a", errors)
        self.assertIn("missing_id:node", errors)
        self.assertIn("dangling_relationship:synthetic-r:tail", errors)
        self.assertIn("missing_vector:synthetic-b", errors)

    def test_plan_parameterizes_values_and_preserves_shared_ids(self):
        nodes = [
            {
                **self.nodes[0],
                "properties": {"text": "literal ' unsafe-looking $value"},
            },
            self.nodes[1],
        ]
        plan = graph_plan(
            nodes, self.relationships, self.vectors, ["SYNTHETIC_RELATION"], 2
        )
        self.assertEqual(
            plan,
            graph_plan(
                nodes, self.relationships, self.vectors, ["SYNTHETIC_RELATION"], 2
            ),
        )
        self.assertEqual(plan["revision"], plan["vector_sync"]["revision"])
        self.assertEqual(
            plan["vector_sync"]["expected_ids"], ["synthetic-a", "synthetic-b"]
        )
        for write in plan["graph_writes"]:
            self.assertIn("$rows", write["query"])
            self.assertNotIn("unsafe-looking", write["query"])
            for row in write["parameters"]["rows"]:
                self.assertEqual(row["properties"]["_sync_revision"], plan["revision"])
        for vector in plan["vector_sync"]["upsert"]:
            self.assertEqual(vector["metadata"]["_sync_revision"], plan["revision"])

    def test_relation_allowlist_and_external_vectors_required(self):
        for allowlist in [[], ["SYNTHETIC_RELATION` MATCH (n)"]]:
            with self.assertRaises(ValueError):
                graph_plan(self.nodes, self.relationships, self.vectors, allowlist, 2)
        for values in [[0.1], [True, 0.2], [float("nan"), 0.2]]:
            with self.assertRaises(ValueError):
                graph_plan(
                    self.nodes,
                    self.relationships,
                    [{**self.vectors[0], "values": values}, self.vectors[1]],
                    ["SYNTHETIC_RELATION"],
                    2,
                )


class NegationTests(unittest.TestCase):
    def test_external_config_required_and_exact_spans(self):
        self.assertEqual(observe_negation("synthetic fixture")["status"], "unresolved")

        def detector(text, config):
            return [{"cue": "fixture", "start": 10, "end": 17}]

        result = observe_negation("synthetic fixture", detector, {"external": True})
        self.assertEqual(result["status"], "observed")
        self.assertIsNone(result["semantic_verdict"])
        for cue in [
            {"cue": "wrong", "start": 10, "end": 17},
            {"cue": "x", "start": True, "end": 2},
            {"cue": "x", "start": 0, "end": 99},
        ]:
            with self.assertRaises(ValueError):
                observe_negation(
                    "synthetic fixture", lambda text, config: [cue], {"external": True}
                )


class GroundingTests(unittest.TestCase):
    def test_missing_evaluator_evidence_and_unknown_ids(self):
        self.assertEqual(evaluate_grounding("synthetic claim")["status"], "unresolved")
        sources = [{"source_id": "synthetic-source", "text": "synthetic evidence"}]

        def callback(claim, evidence):
            return {
                "source_ids": ["synthetic-source"],
                "result": {"external_fixture": True},
            }

        result = evaluate_grounding(
            "synthetic claim", ["synthetic-source"], sources, callback
        )
        self.assertEqual(result["status"], "external_result")
        self.assertNotIn("score", result)
        with self.assertRaises(ValueError):
            evaluate_grounding("synthetic claim", ["unknown"], sources, callback)
        with self.assertRaises(ValueError):
            evaluate_grounding(
                "synthetic claim",
                ["synthetic-source"],
                sources,
                lambda claim, evidence: {"source_ids": ["unknown"], "result": {}},
            )


class EvidencePackageTests(unittest.TestCase):
    def test_deterministic_join_pending_l4_and_isolated_payload(self):
        sources = [{"source_id": "synthetic-b"}, {"source_id": "synthetic-a"}]
        layers = {"L0": {"status": "passed", "passed": True}}
        first = package_evidence(
            "synthetic claim", ["synthetic-b", "synthetic-a"], sources, layers
        )
        second = package_evidence(
            "synthetic claim",
            ["synthetic-a", "synthetic-b"],
            list(reversed(sources)),
            layers,
        )
        self.assertEqual(first, second)
        self.assertEqual(
            first["L4"], {"status": "pending", "authority": "Claude", "decision": None}
        )
        self.assertEqual(first["layers"]["L3"]["status"], "unresolved")
        layers["L0"]["status"] = "modified"
        self.assertEqual(first["layers"]["L0"]["status"], "passed")
        with self.assertRaises(ValueError):
            package_evidence("synthetic claim", ["unknown"], sources, {})
        with self.assertRaises(ValueError):
            package_evidence(
                "synthetic claim",
                ["synthetic-a"],
                sources,
                {"L3": {"evaluation": {"source_ids": ["synthetic-b"]}}},
            )


if __name__ == "__main__":
    unittest.main()
