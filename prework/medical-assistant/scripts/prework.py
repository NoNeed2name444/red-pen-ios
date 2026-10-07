"""Provisional offline plumbing; content and policy decisions are external."""

import argparse
import hashlib
import importlib
import json
import math
import os
import re
import tempfile
import unicodedata
from pathlib import Path

DIRECTORIES = ("app", "data", "docs", "scripts", "tests", ".github/workflows")
VERSION = 1
NODE_KINDS = ("Disease", "Drug", "Symptom", "Procedure")


def canonical(value) -> bytes:
    return json.dumps(
        value, sort_keys=True, ensure_ascii=False, allow_nan=False
    ).encode("utf-8")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def atomic_write(path: Path, content: bytes) -> None:
    """Replace complete artifacts atomically; identical writes are no-ops."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == content:
        return
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=".prework-")
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def bounded_path(root: Path, relative: str) -> Path:
    """Reject absolute paths, traversal, and symlink escapes."""
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError("Expected a nonempty relative path")
    if ".." in Path(relative).parts:
        raise ValueError("Path traversal is forbidden")
    resolved = (root.resolve() / relative).resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ValueError("Path escapes configured root")
    return resolved


def license_flags(record: dict) -> list[str]:
    """Check caller attestation, not the legal truth of source claims."""
    license_record = record.get("license", {})
    if not isinstance(license_record, dict):
        return ["item_license_unverified"]
    identifier = license_record.get("id", "")
    if not isinstance(identifier, str) or not (
        identifier == "unrestricted"
        or re.fullmatch(r"CC-BY(?:-(?:1\.0|2\.0|2\.5|3\.0|4\.0))?", identifier)
    ):
        return ["license_disallowed_or_unknown"]
    evidence = license_record.get("evidence")
    if (
        license_record.get("verified") is not True
        or license_record.get("scope") != "item"
        or license_record.get("item_id") != record.get("id")
        or not isinstance(evidence, list)
        or not evidence
        or any(
            not isinstance(item, dict)
            or item.get("item_id") != record.get("id")
            or not isinstance(item.get("url"), str)
            or not item["url"].strip()
            or not isinstance(item.get("terms"), str)
            or not item["terms"].strip()
            for item in evidence
        )
    ):
        return ["item_specific_evidence_missing_or_unverified"]
    return []


def standardize_image(path: Path) -> bytes:
    """Optional Pillow adapter: RGB PNG; unavailable without Pillow."""
    try:
        from PIL import Image
    except ImportError as error:
        raise RuntimeError(
            "Image standardization unavailable: install Pillow"
        ) from error
    import io

    with Image.open(path) as image:
        output = io.BytesIO()
        image.convert("RGB").save(output, format="PNG")
        return output.getvalue()


def read_jsonl(path: Path) -> list[dict]:
    records = [
        json.loads(line) for line in path.read_text().splitlines() if line.strip()
    ]
    if any(not isinstance(record, dict) for record in records):
        raise ValueError("Each JSONL record must be an object")
    return records


def validate_labels(value, schema: dict) -> None:
    """Fail closed on unsupported schema features; no medical labels default."""
    supported = {
        "type",
        "properties",
        "required",
        "additionalProperties",
        "items",
        "enum",
    }
    if not isinstance(schema, dict) or not schema or set(schema) - supported:
        raise ValueError("Caller schema required; unsupported schema keyword")
    types = {
        "object": lambda item: isinstance(item, dict),
        "array": lambda item: isinstance(item, list),
        "string": lambda item: isinstance(item, str),
        "number": lambda item: type(item) in (int, float),
        "integer": lambda item: type(item) is int,
        "boolean": lambda item: type(item) is bool,
        "null": lambda item: item is None,
    }
    kind = schema.get("type")
    if kind not in types or not types[kind](value):
        raise ValueError("Value does not match caller schema type")
    if "enum" in schema and (
        not isinstance(schema["enum"], list)
        or not schema["enum"]
        or canonical(value) not in [canonical(item) for item in schema["enum"]]
    ):
        raise ValueError("Value is outside caller schema enum")
    if kind == "object":
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        extra = schema.get("additionalProperties", True)
        if (
            not isinstance(properties, dict)
            or not isinstance(required, list)
            or any(not isinstance(item, str) for item in required)
            or type(extra) is not bool
        ):
            raise ValueError("Malformed caller object schema")
        if any(item not in value for item in required):
            raise ValueError("Caller schema required field missing")
        if not extra and set(value) - set(properties):
            raise ValueError("Unexpected label fields")
        for name, child in properties.items():
            # Validate unused definitions too, preventing hidden unsupported rules.
            validate_schema(child)
            if name in value:
                validate_labels(value[name], child)
    if kind == "array":
        if "items" not in schema:
            raise ValueError("Caller array schema requires items")
        validate_schema(schema["items"])
        for item in value:
            validate_labels(item, schema["items"])


def validate_schema(schema: dict) -> None:
    """Check supported schema definitions independently of supplied values."""
    if not isinstance(schema, dict) or "type" not in schema:
        raise ValueError("Explicit caller schema required")
    examples = {
        "object": {},
        "array": [],
        "string": "",
        "number": 0.0,
        "integer": 0,
        "boolean": False,
        "null": None,
    }
    kind = schema["type"]
    if kind not in examples:
        raise ValueError("Unsupported schema type")
    probe = dict(schema)
    probe.pop("enum", None)
    if "enum" in schema and (
        not isinstance(schema["enum"], list) or not schema["enum"]
    ):
        raise ValueError("Malformed enum")
    probe.pop("required", None)
    if "required" in schema and (
        not isinstance(schema["required"], list)
        or any(not isinstance(item, str) for item in schema["required"])
    ):
        raise ValueError("Malformed required fields")
    validate_labels(examples[kind], probe)


def validate_l0(record, schema=None) -> dict:
    "Run only caller-supplied supported schema checks; this is not a safety verdict."
    if schema is None:
        return {
            "status": "unresolved",
            "passed": False,
            "errors": ["caller_schema_missing"],
        }
    try:
        validate_schema(schema)
        validate_labels(record, schema)
    except (TypeError, ValueError) as error:
        return {"status": "failed", "passed": False, "errors": [str(error)]}
    return {"status": "passed", "passed": True, "errors": []}


def validate_l1(record, rules=None) -> dict:
    """Check caller-defined finite numeric bounds and optional exact units only."""
    errors = []
    if not isinstance(record, dict):
        return {
            "status": "failed",
            "passed": False,
            "errors": ["record_must_be_object"],
        }
    if not isinstance(rules, dict) or not rules:
        return {
            "status": "failed",
            "passed": False,
            "errors": ["caller_rules_required"],
        }
    for field, rule in rules.items():
        if not isinstance(field, str) or not field:
            errors.append("malformed_rule_field")
            continue
        if not isinstance(rule, dict) or not rule or set(rule) - {"min", "max", "unit"}:
            errors.append(f"malformed_rule:{field}")
            continue
        bounds = {}
        malformed = False
        for bound in ("min", "max"):
            if bound in rule:
                value = rule[bound]
                if type(value) not in (int, float) or (
                    type(value) is float and not math.isfinite(value)
                ):
                    errors.append(f"malformed_{bound}:{field}")
                    malformed = True
                else:
                    bounds[bound] = value
        if "unit" in rule and (not isinstance(rule["unit"], str) or not rule["unit"]):
            errors.append(f"malformed_unit:{field}")
            malformed = True
        if "min" not in rule and "max" not in rule and "unit" not in rule:
            errors.append(f"empty_rule:{field}")
            malformed = True
        if "min" in bounds and "max" in bounds and bounds["min"] > bounds["max"]:
            errors.append(f"malformed_bounds:{field}")
            malformed = True
        if malformed:
            continue
        if field not in record:
            errors.append(f"missing_field:{field}")
            continue
        supplied = record[field]
        if "unit" in rule:
            if not isinstance(supplied, dict) or set(supplied) != {"value", "unit"}:
                errors.append(f"value_and_unit_required:{field}")
                continue
            if supplied["unit"] != rule["unit"]:
                errors.append(f"unit_mismatch:{field}")
                continue
            supplied = supplied["value"]
        if type(supplied) not in (int, float) or (
            type(supplied) is float and not math.isfinite(supplied)
        ):
            errors.append(f"finite_number_required:{field}")
            continue
        if "min" in bounds and supplied < bounds["min"]:
            errors.append(f"below_min:{field}")
        if "max" in bounds and supplied > bounds["max"]:
            errors.append(f"above_max:{field}")
    return {
        "status": "passed" if not errors else "failed",
        "passed": not errors,
        "errors": errors,
    }


def annotate(
    manifests: list[dict], annotations: list[dict], schema: dict, output: Path
):
    """Validate complete caller labels before atomically exporting JSONL."""
    validate_schema(schema)
    eligible = {
        item["manifest_id"]
        for item in manifests
        if item.get("exclusion_flags") == []
        and not license_flags(
            {
                **item,
                "id": item.get("item_id"),
            }
        )
    }
    seen = set()
    for annotation in annotations:
        if set(annotation) != {"manifest_id", "labels"}:
            raise ValueError("Annotation requires manifest_id and labels only")
        identifier = annotation["manifest_id"]
        if identifier not in eligible or identifier in seen:
            raise ValueError("Unknown, excluded, or duplicate manifest id")
        seen.add(identifier)
        validate_labels(annotation["labels"], schema)
    atomic_write(output, b"".join(canonical(item) + b"\n" for item in annotations))
    return annotations


def load_callback(specification: str):
    """Load an explicitly supplied trusted module:function; no default provider."""
    module_name, separator, attribute = specification.partition(":")
    if not separator or not module_name or not attribute:
        raise ValueError("Callback requires module:function")
    callback = getattr(importlib.import_module(module_name), attribute)
    if not callable(callback):
        raise ValueError("Configured callback is not callable")
    return callback


def observe_negation(text: str, detector=None, cue_config=None) -> dict:
    """L2 external cue/span observations; no semantic negation verdict."""
    if not callable(detector) or not isinstance(cue_config, dict) or not cue_config:
        return {
            "layer": "L2",
            "status": "unresolved",
            "cues": [],
            "reason": "external_detector_or_cue_config_missing",
        }
    if not isinstance(text, str):
        raise ValueError("Caller text must be a string")
    cues = detector(text, cue_config)
    if not isinstance(cues, list):
        raise ValueError("Detector must return cue/span objects")
    for cue in cues:
        if not isinstance(cue, dict) or set(cue) != {"cue", "start", "end"}:
            raise ValueError("Cue requires cue/start/end")
        start, end = cue["start"], cue["end"]
        if (
            type(start) is not int
            or type(end) is not int
            or not 0 <= start < end <= len(text)
        ):
            raise ValueError("Cue spans must be valid text offsets")
        if cue["cue"] != text[start:end]:
            raise ValueError("Cue must match exact source text span")
    return {"layer": "L2", "status": "observed", "cues": cues, "semantic_verdict": None}


def exact_sources(source_ids: list[str], provenance: list[dict]) -> list[dict]:
    """Join only explicit, unique, exact source identifiers."""
    if not isinstance(source_ids, list) or any(
        not isinstance(item, str) or not item for item in source_ids
    ):
        raise ValueError("Explicit source ID list required")
    if len(set(source_ids)) != len(source_ids):
        raise ValueError("Duplicate evidence source IDs")
    registry = {}
    for source in provenance:
        identifier = source.get("source_id")
        if not isinstance(identifier, str) or not identifier or identifier in registry:
            raise ValueError("Missing or duplicate provenance source IDs")
        registry[identifier] = source
    if set(source_ids) - set(registry):
        raise ValueError("Evidence references unknown exact source IDs")
    return [registry[identifier] for identifier in sorted(source_ids)]


def evaluate_grounding(
    claim: str, source_ids=None, provenance=None, evaluator=None
) -> dict:
    """L3 external evaluation; no inferred score or semantic verdict."""
    if not source_ids or not provenance or not callable(evaluator):
        return {
            "layer": "L3",
            "status": "unresolved",
            "reason": "external_evaluator_or_evidence_missing",
        }
    evidence = exact_sources(source_ids, provenance)
    if not isinstance(claim, str) or not claim.strip():
        raise ValueError("Caller claim required")
    result = evaluator(claim, evidence)
    if (
        not isinstance(result, dict)
        or set(result) != {"source_ids", "result"}
        or not isinstance(result["result"], dict)
    ):
        raise ValueError("Evaluator requires source_ids and external result object")
    if not result["source_ids"]:
        raise ValueError("Evaluator must cite supplied evidence")
    exact_sources(result["source_ids"], evidence)
    canonical(result)
    return {"layer": "L3", "status": "external_result", "evaluation": result}


def package_evidence(
    claim: str, source_ids: list[str], provenance: list[dict], layers: dict
) -> dict:
    """L4 preparation only: join provenance and prior results, never approve."""
    if not isinstance(claim, str) or not claim.strip():
        raise ValueError("Caller claim required")
    if not isinstance(layers, dict) or set(layers) - {"L0", "L1", "L2", "L3"}:
        raise ValueError("Only caller L0-L3 results may be packaged")
    joined = exact_sources(source_ids, provenance)
    normalized = {}
    for name in ("L0", "L1", "L2", "L3"):
        result = layers.get(
            name, {"status": "unresolved", "reason": "layer_result_missing"}
        )
        if not isinstance(result, dict):
            raise ValueError("Layer result must be an object")
        normalized[name] = result
    evaluation = normalized["L3"].get("evaluation")
    if evaluation:
        exact_sources(evaluation.get("source_ids"), joined)
    package = {
        "version": VERSION,
        "status": "pending",
        "claim": claim,
        "source_ids": sorted(source_ids),
        "provenance": joined,
        "layers": normalized,
        "L4": {"status": "pending", "authority": "Claude", "decision": None},
    }
    package = json.loads(canonical(package))
    return {"package_id": digest(canonical(package)), **package}


def resolve_entity(query: str, system: str, adapter=None) -> dict:
    """No terminology lookup occurs without a caller-supplied adapter."""
    if system not in {"UMLS", "SNOMED CT", "ICD11"}:
        raise ValueError("Unknown external terminology system")
    if adapter is None:
        return {
            "system": system,
            "query": query,
            "status": "unresolved",
            "reason": "External terminology adapter and credentials absent",
        }
    result = adapter(query)
    if not isinstance(result, dict):
        raise ValueError("External entity adapter must return an object")
    return {
        "system": system,
        "query": query,
        "status": "external_result",
        "result": result,
    }


def extract_triplets(manifests: list[dict], extractor, output: Path) -> list[dict]:
    """Validate external triples and exact evidence IDs; never invent relations."""
    if not callable(extractor):
        raise ValueError("External extractor callback required")
    eligible = {}
    for item in manifests:
        if item.get("exclusion_flags") == [] and not license_flags(
            {
                **item,
                "id": item.get("item_id"),
            }
        ):
            identifier = item.get("manifest_id")
            if (
                not isinstance(identifier, str)
                or not identifier
                or identifier in eligible
            ):
                raise ValueError("Invalid or duplicate manifest IDs")
            eligible[identifier] = item
    triples = {}
    for identifier, item in eligible.items():
        supplied = extractor(item)
        if not isinstance(supplied, list):
            raise ValueError("Extractor must return a list of triple objects")
        for triple in supplied:
            if not isinstance(triple, dict) or set(triple) != {
                "head",
                "relation",
                "tail",
                "source_ids",
            }:
                raise ValueError("Triple requires head, relation, tail, source_ids")
            if any(
                not isinstance(triple[key], str) or not triple[key].strip()
                for key in ("head", "relation", "tail")
            ):
                raise ValueError("Triple members must be nonempty strings")
            sources = triple["source_ids"]
            if (
                not isinstance(sources, list)
                or not sources
                or any(not isinstance(source, str) for source in sources)
                or len(set(sources)) != len(sources)
                or identifier not in sources
                or set(sources) - set(eligible)
            ):
                raise ValueError("Triple evidence must cite qualified manifest IDs")
            normalized = {**triple, "source_ids": sorted(sources), "version": VERSION}
            triplet_id = digest(canonical(normalized))
            triples[triplet_id] = {"triplet_id": triplet_id, **normalized}
    result = [triples[key] for key in sorted(triples)]
    atomic_write(output, b"".join(canonical(item) + b"\n" for item in result))
    return result


def graph_integrity(
    nodes: list[dict], relationships: list[dict], vectors: list[dict]
) -> list[str]:
    """Compare caller graph/vector IDs without assigning medical semantics."""
    errors = []
    identifiers = {}
    for kind, records in (
        ("node", nodes),
        ("relationship", relationships),
        ("vector", vectors),
    ):
        seen = set()
        for record in records:
            identifier = record.get("id")
            if not isinstance(identifier, str) or not identifier.strip():
                errors.append(f"missing_id:{kind}")
            elif identifier in seen:
                errors.append(f"duplicate_id:{kind}:{identifier}")
            else:
                seen.add(identifier)
        identifiers[kind] = seen
    for relationship in relationships:
        for endpoint in ("head", "tail"):
            if relationship.get(endpoint) not in identifiers["node"]:
                errors.append(
                    f"dangling_relationship:{relationship.get('id')}:{endpoint}"
                )
    errors.extend(
        f"missing_vector:{identifier}"
        for identifier in sorted(identifiers["node"] - identifiers["vector"])
    )
    errors.extend(
        f"missing_node:{identifier}"
        for identifier in sorted(identifiers["vector"] - identifiers["node"])
    )
    return errors


def graph_plan(nodes, relationships, vectors, relation_types, dimensions: int) -> dict:
    """Prepare parameterized writes and a vector protocol; execute no database IO."""
    errors = graph_integrity(nodes, relationships, vectors)
    if errors:
        raise ValueError("Graph/vector integrity failed: " + ", ".join(errors))
    if type(dimensions) is not int or dimensions <= 0:
        raise ValueError("Caller vector dimensions required")
    if not isinstance(relation_types, list) or any(
        not isinstance(kind, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", kind)
        for kind in relation_types
    ):
        raise ValueError("Caller relationship type allowlist required")
    for node in nodes:
        if node.get("kind") not in NODE_KINDS:
            raise ValueError(
                "Node kind must be caller-assigned Disease/Drug/Symptom/Procedure"
            )
    for relation in relationships:
        if relation.get("type") not in relation_types:
            raise ValueError("Relationship type outside caller allowlist")
    for item in [*nodes, *relationships]:
        properties = item.get("properties", {})
        if not isinstance(properties, dict) or "id" in properties:
            raise ValueError("Properties must be an object without an id override")
    for vector in vectors:
        values = vector.get("values")
        if (
            not isinstance(values, list)
            or len(values) != dimensions
            or any(
                type(value) not in (int, float) or not math.isfinite(value)
                for value in values
            )
        ):
            raise ValueError(
                "Embedding must have caller dimensions and finite numeric values"
            )
    revision = digest(
        canonical({"nodes": nodes, "relationships": relationships, "vectors": vectors})
    )
    writes = []
    for kind in NODE_KINDS:
        rows = [
            {
                "id": item["id"],
                "properties": {
                    **item.get("properties", {}),
                    "_sync_revision": revision,
                },
            }
            for item in nodes
            if item["kind"] == kind
        ]
        if rows:
            writes.append(
                {
                    "query": (
                        f"UNWIND $rows AS row MERGE (n:Entity:{kind} {{id: row.id}}) "
                        "SET n += row.properties"
                    ),
                    "parameters": {"rows": rows},
                }
            )
    for kind in sorted(set(relation_types)):
        rows = [
            {
                "id": item["id"],
                "head": item["head"],
                "tail": item["tail"],
                "properties": {
                    **item.get("properties", {}),
                    "_sync_revision": revision,
                },
            }
            for item in relationships
            if item["type"] == kind
        ]
        if rows:
            writes.append(
                {
                    "query": "UNWIND $rows AS row MATCH (h:Entity {id: row.head}), "
                    "(t:Entity {id: row.tail}) "
                    f"MERGE (h)-[r:{kind} {{id: row.id}}]->(t) SET r += row.properties",
                    "parameters": {"rows": rows},
                }
            )
    return {
        "version": VERSION,
        "revision": revision,
        "graph_writes": writes,
        "vector_sync": {
            "revision": revision,
            "id_field": "id",
            "dimensions": dimensions,
            "upsert": [
                {
                    "id": item["id"],
                    "values": item["values"],
                    "metadata": {"_sync_revision": revision},
                }
                for item in vectors
            ],
            "expected_ids": sorted(item["id"] for item in nodes),
        },
        "protocol": [
            "caller applies graph transaction",
            "caller upserts vectors with same IDs and revision",
            "caller reads both stores and verifies expected IDs and revision "
            "before marking synchronized",
        ],
    }


def etl(
    input_path: Path,
    output: Path,
    assets: Path,
    image_adapter=None,
    image_adapter_id: str | None = None,
) -> list[dict]:
    """Normalize caller inputs with durable per-item checkpoints and stable IDs."""
    records = read_jsonl(input_path)
    if image_adapter is not None and not image_adapter_id:
        raise ValueError("Custom image adapters require a versioned image_adapter_id")
    ids = [record.get("id") for record in records]
    if any(not isinstance(item, str) or not item.strip() for item in ids):
        raise ValueError("Each item requires a nonempty id")
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate input ids")
    checkpoint_path = bounded_path(output, "checkpoint.json")
    checkpoint = (
        json.loads(checkpoint_path.read_text()) if checkpoint_path.exists() else {}
    )
    manifests = []
    for record in records:
        if not isinstance(record.get("source"), str) or not record["source"].strip():
            raise ValueError("Each item requires a source")
        flags = license_flags(record)
        image_path = None
        image_source_hash = None
        if not flags and record.get("image"):
            image_path = bounded_path(assets, record["image"])
            image_source_hash = digest(image_path.read_bytes())
        key = digest(
            canonical(
                {
                    "version": VERSION,
                    "record": record,
                    "image_source_sha256": image_source_hash,
                    "image_adapter_id": image_adapter_id or "pillow-rgb-png-v1",
                }
            )
        )
        cached = checkpoint.get(key)
        if cached:
            artifact = bounded_path(output, f"objects/{cached}.json")
            if artifact.exists():
                payload = artifact.read_bytes()
                if digest(payload) == cached:
                    entry = json.loads(payload)
                    image = entry.get("image")
                    if not image or (
                        bounded_path(output, image["path"]).is_file()
                        and digest(bounded_path(output, image["path"]).read_bytes())
                        == image["sha256"]
                    ):
                        manifests.append({"manifest_id": cached, **entry})
                        continue
        entry = {
            "version": VERSION,
            "item_id": record["id"],
            "source": record["source"],
            "label": record.get("label"),
            "split": record.get("split"),
            "license": record.get("license"),
            "statistics": {"characters": 0, "tokens": 0, "image_bytes": 0},
            "exclusion_flags": flags,
        }
        if not flags:
            text = record.get("text", "")
            if not isinstance(text, str):
                raise ValueError("Text must be a string")
            text = " ".join(unicodedata.normalize("NFKC", text).split())
            entry["text"] = text
            entry["tokens"] = re.findall(r"\w+|[^\w\s]", text)
            entry["statistics"].update(
                characters=len(text), tokens=len(entry["tokens"])
            )
            if record.get("image"):
                image_content = (image_adapter or standardize_image)(image_path)
                if not isinstance(image_content, bytes) or not image_content:
                    raise ValueError("Image adapter must return nonempty bytes")
                image_hash = digest(image_content)
                image_name = f"images/{image_hash}.png"
                atomic_write(bounded_path(output, image_name), image_content)
                entry["image"] = {
                    "path": image_name,
                    "sha256": image_hash,
                    "source_sha256": image_source_hash,
                    "adapter_id": image_adapter_id or "pillow-rgb-png-v1",
                }
                entry["statistics"]["image_bytes"] = len(image_content)
        payload = canonical(entry)
        manifest_id = digest(payload)
        atomic_write(bounded_path(output, f"objects/{manifest_id}.json"), payload)
        checkpoint[key] = manifest_id
        atomic_write(checkpoint_path, canonical(checkpoint))
        manifests.append({"manifest_id": manifest_id, **entry})
    atomic_write(
        bounded_path(output, "manifest.jsonl"),
        b"".join(canonical(item) + b"\n" for item in manifests),
    )
    return manifests


def missing_directories(root: Path) -> list[str]:
    """Return required paths that are absent or are not directories."""
    return [name for name in DIRECTORIES if not (root / name).is_dir()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command")
    etl_parser = subcommands.add_parser("etl")
    etl_parser.add_argument("input", type=Path)
    etl_parser.add_argument("output", type=Path)
    etl_parser.add_argument("--assets", type=Path, required=True)
    annotation_parser = subcommands.add_parser("annotate")
    annotation_parser.add_argument("manifest", type=Path)
    annotation_parser.add_argument("annotations", type=Path)
    annotation_parser.add_argument("schema", type=Path)
    annotation_parser.add_argument("output", type=Path)
    triplet_parser = subcommands.add_parser("triplets")
    triplet_parser.add_argument("manifest", type=Path)
    triplet_parser.add_argument("output", type=Path)
    triplet_parser.add_argument("--extractor", required=True)
    entity_parser = subcommands.add_parser("entity-stub")
    entity_parser.add_argument("system", choices=["UMLS", "SNOMED CT", "ICD11"])
    entity_parser.add_argument("query")
    graph_parser = subcommands.add_parser("graph-plan")
    graph_parser.add_argument("input", type=Path)
    graph_parser.add_argument("output", type=Path)
    l0_parser = subcommands.add_parser("l0", help="mechanically check caller schema")
    l0_parser.add_argument("record", type=Path)
    l0_parser.add_argument("--schema", type=Path)
    l1_parser = subcommands.add_parser("l1", help="check caller numeric rules")
    l1_parser.add_argument("record", type=Path)
    l1_parser.add_argument("rules", type=Path)
    l2_parser = subcommands.add_parser("l2", help="external cue/span observations")
    l2_parser.add_argument("record", type=Path)
    l2_parser.add_argument("--config", type=Path)
    l2_parser.add_argument("--detector")
    l3_parser = subcommands.add_parser("l3", help="external grounding evaluator")
    l3_parser.add_argument("input", type=Path)
    l3_parser.add_argument("--evaluator")
    l4_parser = subcommands.add_parser(
        "l4", help="package evidence for pending Claude review"
    )
    l4_parser.add_argument("input", type=Path)
    l4_parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    if arguments.command == "etl":
        manifests = etl(arguments.input, arguments.output, arguments.assets)
        print(json.dumps({"records": len(manifests), "output": str(arguments.output)}))
        return 0
    if arguments.command == "annotate":
        result = annotate(
            read_jsonl(arguments.manifest),
            read_jsonl(arguments.annotations),
            json.loads(arguments.schema.read_text()),
            arguments.output,
        )
        print(json.dumps({"annotations": len(result)}))
        return 0
    if arguments.command == "triplets":
        result = extract_triplets(
            read_jsonl(arguments.manifest),
            load_callback(arguments.extractor),
            arguments.output,
        )
        print(json.dumps({"triplets": len(result)}))
        return 0
    if arguments.command == "entity-stub":
        print(json.dumps(resolve_entity(arguments.query, arguments.system)))
        return 0
    if arguments.command == "graph-plan":
        supplied = json.loads(arguments.input.read_text())
        plan = graph_plan(
            supplied["nodes"],
            supplied["relationships"],
            supplied["vectors"],
            supplied["relation_types"],
            supplied["dimensions"],
        )
        atomic_write(arguments.output, canonical(plan))
        print(json.dumps({"revision": plan["revision"], "execution": "not_performed"}))
        return 0
    if arguments.command == "l0":
        record = json.loads(arguments.record.read_text())
        schema = json.loads(arguments.schema.read_text()) if arguments.schema else None
        result = validate_l0(record, schema)
        print(json.dumps(result))
        return 0 if result["passed"] else 1
    if arguments.command == "l2":
        text = json.loads(arguments.record.read_text())["text"]
        config = json.loads(arguments.config.read_text()) if arguments.config else None
        detector = load_callback(arguments.detector) if arguments.detector else None
        result = observe_negation(text, detector, config)
        print(json.dumps(result))
        return 1 if result["status"] == "unresolved" else 0
    if arguments.command == "l3":
        supplied = json.loads(arguments.input.read_text())
        evaluator = load_callback(arguments.evaluator) if arguments.evaluator else None
        result = evaluate_grounding(
            supplied["claim"],
            supplied.get("source_ids"),
            supplied.get("provenance"),
            evaluator,
        )
        print(json.dumps(result))
        return 1 if result["status"] == "unresolved" else 0
    if arguments.command == "l4":
        supplied = json.loads(arguments.input.read_text())
        result = package_evidence(
            supplied["claim"],
            supplied["source_ids"],
            supplied["provenance"],
            supplied["layers"],
        )
        atomic_write(arguments.output, canonical(result))
        print(json.dumps({"package_id": result["package_id"], "L4": "pending"}))
        return 0
    if arguments.command == "l1":
        record = json.loads(arguments.record.read_text())
        rules = json.loads(arguments.rules.read_text())
        result = validate_l1(record, rules)
        print(json.dumps(result))
        return 0 if result["passed"] else 1
    root = Path(__file__).resolve().parents[1]
    missing = missing_directories(root)
    if missing:
        print("Missing scaffold directories: " + ", ".join(missing))
        return 1
    print("Scaffold layout OK; application and provider setup remain pending.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
