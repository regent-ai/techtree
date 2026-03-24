from __future__ import annotations

import json
from pathlib import Path

from .bbh_models import (
    BbhArtifactSourceV1,
    BbhGenomeSourceV1,
    BbhReviewSourceV1,
    BbhRunSourceV1,
)
from .models import (
    ArtifactManifestV1,
    ArtifactSourceV1,
    NodeHeaderV1,
    PayloadIndexV1,
    ReviewManifestV1,
    ReviewSourceV1,
    RunManifestV1,
    RunSourceV1,
)


SCHEMA_FILES = {
    "artifact-source.v1.schema.json": ArtifactSourceV1,
    "run-source.v1.schema.json": RunSourceV1,
    "review-source.v1.schema.json": ReviewSourceV1,
    "techtree.bbh.artifact-source.v1.schema.json": BbhArtifactSourceV1,
    "techtree.bbh.genome-source.v1.schema.json": BbhGenomeSourceV1,
    "techtree.bbh.run-source.v1.schema.json": BbhRunSourceV1,
    "techtree.bbh.review-source.v1.schema.json": BbhReviewSourceV1,
    "payload-index.v1.schema.json": PayloadIndexV1,
    "artifact-manifest.v1.schema.json": ArtifactManifestV1,
    "run-manifest.v1.schema.json": RunManifestV1,
    "review-manifest.v1.schema.json": ReviewManifestV1,
    "node-header.v1.schema.json": NodeHeaderV1,
}


def export_all_schemas(output_dir: Path) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    written: dict[str, Path] = {}
    for filename, model in SCHEMA_FILES.items():
        schema = model.model_json_schema(ref_template="#/$defs/{model}")
        path = output_dir / filename
        path.write_text(json.dumps(schema, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        written[filename] = path
    return written
