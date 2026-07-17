"""Configure a Hermes home for an air-gapped Windows installation."""

from __future__ import annotations

import argparse
import json
import os
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import TypeAlias

import yaml

YamlValue: TypeAlias = (
    str | int | float | bool | None | list["YamlValue"] | dict[str, "YamlValue"]
)

_COMMIT_RE = re.compile(r"[0-9a-fA-F]{7,40}")


def _read_config(config_path: Path) -> dict[str, YamlValue]:
    if not config_path.exists():
        return {}

    loaded = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if loaded is None:
        return {}
    if not isinstance(loaded, dict) or not all(isinstance(key, str) for key in loaded):
        raise ValueError(f"Hermes config must be a string-keyed mapping: {config_path}")
    return loaded


def _offline_config(config: dict[str, YamlValue]) -> dict[str, YamlValue]:
    updated = dict(config)
    raw_security = updated.get("security")
    if raw_security is None:
        security: dict[str, YamlValue] = {}
    elif isinstance(raw_security, dict) and all(
        isinstance(key, str) for key in raw_security
    ):
        security = dict(raw_security)
    else:
        raise ValueError(
            "Hermes config field 'security' must be a string-keyed mapping"
        )
    security["allow_lazy_installs"] = False
    updated["security"] = security
    return updated


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary_path.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary_path, path)


def configure_offline(config_path: Path, marker_path: Path, commit: str) -> None:
    """Disable runtime installs and write a valid desktop bootstrap marker."""

    if _COMMIT_RE.fullmatch(commit) is None:
        raise ValueError("commit must contain 7 to 40 hexadecimal characters")

    config = _offline_config(_read_config(config_path))
    marker = {
        "schemaVersion": 1,
        "pinnedCommit": commit.lower(),
        "pinnedBranch": "offline",
        "completedAt": datetime
        .now(UTC)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
    }
    config_text = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    marker_text = json.dumps(marker, indent=2, ensure_ascii=False) + "\n"
    _atomic_write(config_path, config_text)
    _atomic_write(marker_path, marker_text)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--marker", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    configure_offline(args.config, args.marker, args.commit)


if __name__ == "__main__":
    main()
