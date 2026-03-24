from __future__ import annotations

import hashlib
import json
from typing import Any


def _escape_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _format_float(value: float) -> str:
    if value != value or value in (float("inf"), float("-inf")):
        raise ValueError("Non-finite numbers are not permitted in canonical JSON")
    if value == 0.0:
        return "0"
    text = format(value, ".15g")
    if "e" in text or "E" in text:
        mantissa, exponent = text.lower().split("e", 1)
        sign = ""
        if exponent.startswith(("+", "-")):
            sign = exponent[0]
            exponent = exponent[1:]
        exponent = exponent.lstrip("0") or "0"
        if sign == "+":
            sign = ""
        text = f"{mantissa}e{sign}{exponent}"
    return text


def canonicalize(value: Any) -> bytes:
    def render(item: Any) -> str:
        if item is None:
            return "null"
        if item is True:
            return "true"
        if item is False:
            return "false"
        if isinstance(item, int) and not isinstance(item, bool):
            return str(item)
        if isinstance(item, float):
            return _format_float(item)
        if isinstance(item, str):
            return _escape_string(item)
        if isinstance(item, list):
            return "[" + ",".join(render(entry) for entry in item) + "]"
        if isinstance(item, tuple):
            return "[" + ",".join(render(entry) for entry in item) + "]"
        if isinstance(item, dict):
            parts = []
            for key in sorted(item.keys()):
                if not isinstance(key, str):
                    raise TypeError("Canonical JSON object keys must be strings")
                parts.append(f"{_escape_string(key)}:{render(item[key])}")
            return "{" + ",".join(parts) + "}"
        raise TypeError(f"Unsupported canonical JSON type: {type(item)!r}")

    return render(value).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def domain_hash(prefix: str, payload: Any) -> bytes:
    return hashlib.sha256(prefix.encode("utf-8") + b"\0" + canonicalize(payload)).digest()


def sha256_prefixed(prefix: str, payload: Any) -> str:
    return f"sha256:{sha256_hex(domain_hash(prefix, payload))}"


def bytes32_hex_from_digest(digest: bytes) -> str:
    if len(digest) != 32:
        raise ValueError("Expected 32-byte digest")
    return "0x" + digest.hex()

