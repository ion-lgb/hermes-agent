# Windows Offline Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a Windows x64 NSIS installer that installs the Hermes framework without network access and without a model.

**Architecture:** A GitHub Actions Windows job prepares a self-contained payload and passes it to an offline electron-builder configuration. An NSIS custom-install hook runs a local-only provisioning script that creates the final Hermes venv and bootstrap marker.

**Tech Stack:** GitHub Actions, PowerShell 5.1, Python 3.11, uv, Node.js 22, Electron 40, electron-builder 26, NSIS.

## Global Constraints

- The target installer is Windows x64 only.
- No model or model server is included.
- Target-machine provisioning performs no network operations.
- All GitHub Actions are pinned to immutable commit SHAs.
- Existing Hermes configuration is preserved except `security.allow_lazy_installs=false`.
- The installed source snapshot excludes `.git` to prevent update fetches.

---

### Task 1: Offline configuration helper

**Files:**
- Create: `scripts/offline/configure_offline.py`
- Test: `tests/test_offline_configure.py`

**Interfaces:**
- Consumes: a `config.yaml` path and bootstrap-marker path from argv.
- Produces: `configure_offline(config_path: Path, marker_path: Path, commit: str) -> None`.

- [ ] Write tests proving a missing config is created, an existing config is preserved, lazy installs are disabled, and a valid marker is written.
- [ ] Run `scripts/run_tests.sh tests/test_offline_configure.py -q` and confirm the import fails.
- [ ] Implement the typed helper with explicit validation and atomic UTF-8 writes.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: Target-machine provisioning

**Files:**
- Create: `scripts/offline/install-offline.ps1`

**Interfaces:**
- Consumes: `-PayloadRoot`, `-HermesHome`, and `-BrowserCacheRoot`; the commit
  is read from the payload manifest.
- Produces: a runnable `%LOCALAPPDATA%\hermes\hermes-agent\venv` and schema-1 bootstrap marker.

- [ ] Implement payload validation before destination mutation.
- [ ] Copy source, Python, Node, Git, Node dependencies, and Chromium to their canonical locations.
- [ ] Create the venv and install `.[all]` from the wheelhouse with `--no-index --find-links`.
- [ ] Invoke `configure_offline.py` and fail explicitly on any non-zero process exit.
- [ ] Add a PowerShell parser check to the GitHub workflow before packaging.

### Task 3: Managed Node PATH behavior

**Files:**
- Modify: `apps/desktop/electron/backend-env.ts`
- Modify: `apps/desktop/electron/backend-env.test.ts`

**Interfaces:**
- Consumes: `hermesHome`, platform, venv and current PATH.
- Produces: a Windows backend PATH containing both `HERMES_HOME\node` and `HERMES_HOME\node\bin`.

- [ ] Add a failing test for the portable Windows Node root.
- [ ] Run the focused Vitest test and confirm the new assertion fails.
- [ ] Add the platform-ordered root and bin entries.
- [ ] Re-run the focused Vitest test and confirm it passes.

### Task 4: Offline Electron package

**Files:**
- Create: `apps/desktop/electron-builder.offline.cjs`
- Create: `apps/desktop/build/offline-installer.nsh`

**Interfaces:**
- Consumes: `apps/desktop/build/offline-payload` prepared by the workflow.
- Produces: `Hermes-Offline-<version>-windows-x64.exe`.

- [ ] Create a separate config by extending the existing package build data.
- [ ] Add the payload through `extraResources` and point NSIS at the include file.
- [ ] Add `customInstall` to execute the local provisioning script and abort on failure.
- [ ] Remove the embedded payload only after successful provisioning.

### Task 5: Payload builder and GitHub Actions

**Files:**
- Create: `scripts/offline/prepare-windows-payload.ps1`
- Create: `.github/workflows/build-windows-offline.yml`

**Interfaces:**
- Consumes: the checked-out repository, uv, Node 22, and network access on the Actions runner.
- Produces: a complete `apps/desktop/build/offline-payload` directory, NSIS EXE, and SHA-256 file.

- [ ] Stage a clean tracked source snapshot and the installer scripts.
- [ ] Stage managed CPython, uv-built wheelhouse, Node, PortableGit, root Node dependencies, and Playwright Chromium.
- [ ] Add a payload manifest with the source commit and resolved runtime versions.
- [ ] Add a manual `workflow_dispatch` Windows job using immutable action SHAs.
- [ ] Smoke-test provisioning into a temporary Hermes home before building NSIS.
- [ ] Build the offline NSIS target and upload the EXE plus checksum.

### Task 6: Verify and publish

**Files:**
- Modify only files listed above if verification exposes a defect.

**Interfaces:**
- Consumes: the completed implementation.
- Produces: a pushed fork branch and a running GitHub Actions build.

- [ ] Run focused Python and desktop tests.
- [ ] Parse the workflow YAML and PowerShell scripts.
- [ ] Inspect `git --no-pager diff` and confirm only offline-distribution changes are present.
- [ ] Commit, push `agent/windows-offline-installer`, and trigger `build-windows-offline.yml` with `gh workflow run`.
- [ ] Wait for the workflow result and report the artifact or the exact failing build step.
