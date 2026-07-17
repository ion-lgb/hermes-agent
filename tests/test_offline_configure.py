from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

from scripts.offline.configure_offline import configure_offline


def test_configure_offline_creates_restricted_config_and_marker(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / "hermes-agent" / ".hermes-bootstrap-complete"
    env_path = tmp_path / ".env"
    browser_home = tmp_path / "agent-browser"
    browser_executable = browser_home / "browsers" / "chrome" / "chrome.exe"
    commit = "71252f0dcb92b957b45c371d062aa572b8dc4785"

    configure_offline(
        config_path,
        marker_path,
        env_path,
        browser_home,
        browser_executable,
        commit,
    )

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    marker = json.loads(marker_path.read_text(encoding="utf-8"))
    assert config == {"security": {"allow_lazy_installs": False}}
    assert marker["schemaVersion"] == 1
    assert marker["pinnedCommit"] == commit
    assert marker["pinnedBranch"] == "offline"
    assert marker["completedAt"].endswith("Z")
    assert env_path.read_text(encoding="utf-8") == (
        f"AGENT_BROWSER_HOME={browser_home}\n"
        f"AGENT_BROWSER_EXECUTABLE_PATH={browser_executable}\n"
    )


def test_configure_offline_preserves_existing_config_values(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / ".hermes-bootstrap-complete"
    env_path = tmp_path / ".env"
    env_path.write_text(
        "CUSTOM=value\nAGENT_BROWSER_EXECUTABLE_PATH=C:\\old\\chrome.exe\n",
        encoding="utf-8",
    )
    browser_home = tmp_path / "agent-browser"
    browser_executable = browser_home / "chrome.exe"
    config_path.write_text(
        "model:\n  default: local-model\nsecurity:\n  allow_lazy_installs: true\n  approvals: true\n",
        encoding="utf-8",
    )

    configure_offline(
        config_path,
        marker_path,
        env_path,
        browser_home,
        browser_executable,
        "71252f0dcb92b957b45c371d062aa572b8dc4785",
    )

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    assert config["model"] == {"default": "local-model"}
    assert config["security"] == {
        "allow_lazy_installs": False,
        "approvals": True,
    }
    assert env_path.read_text(encoding="utf-8") == (
        "CUSTOM=value\n"
        f"AGENT_BROWSER_HOME={browser_home}\n"
        f"AGENT_BROWSER_EXECUTABLE_PATH={browser_executable}\n"
    )


def test_configure_offline_rejects_invalid_commit_without_writing(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "config.yaml"
    marker_path = tmp_path / ".hermes-bootstrap-complete"
    env_path = tmp_path / ".env"

    with pytest.raises(ValueError, match="7 to 40 hexadecimal"):
        configure_offline(
            config_path,
            marker_path,
            env_path,
            tmp_path / "agent-browser",
            tmp_path / "agent-browser" / "chrome.exe",
            "not-a-commit",
        )

    assert not config_path.exists()
    assert not marker_path.exists()
    assert not env_path.exists()
