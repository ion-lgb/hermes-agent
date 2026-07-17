from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

from scripts.offline.configure_offline import configure_offline


def test_configure_offline_creates_restricted_config_and_marker(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / "hermes-agent" / ".hermes-bootstrap-complete"
    commit = "71252f0dcb92b957b45c371d062aa572b8dc4785"

    configure_offline(config_path, marker_path, commit)

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    marker = json.loads(marker_path.read_text(encoding="utf-8"))
    assert config == {"security": {"allow_lazy_installs": False}}
    assert marker["schemaVersion"] == 1
    assert marker["pinnedCommit"] == commit
    assert marker["pinnedBranch"] == "offline"
    assert marker["completedAt"].endswith("Z")


def test_configure_offline_preserves_existing_config_values(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / ".hermes-bootstrap-complete"
    config_path.write_text(
        "model:\n  default: local-model\nsecurity:\n  allow_lazy_installs: true\n  approvals: true\n",
        encoding="utf-8",
    )

    configure_offline(
        config_path,
        marker_path,
        "71252f0dcb92b957b45c371d062aa572b8dc4785",
    )

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    assert config["model"] == {"default": "local-model"}
    assert config["security"] == {
        "allow_lazy_installs": False,
        "approvals": True,
    }


def test_configure_offline_rejects_invalid_commit_without_writing(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / ".hermes-bootstrap-complete"

    with pytest.raises(ValueError, match="7 to 40 hexadecimal"):
        configure_offline(config_path, marker_path, "not-a-commit")

    assert not config_path.exists()
    assert not marker_path.exists()
