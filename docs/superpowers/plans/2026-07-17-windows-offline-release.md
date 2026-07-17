# Windows Offline Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically rebuild the Windows x64 offline artifact after fork synchronization and optionally publish a manually named GitHub Release.

**Architecture:** The existing Windows build job keeps read-only repository permissions and runs on both `main` pushes and manual dispatches. A separate release job receives only the completed artifact, has `contents: write`, and runs only when a manual dispatch supplies both a release tag and title.

**Tech Stack:** GitHub Actions, GitHub CLI, Windows x64 runner, NSIS, Actions artifacts.

## Global Constraints

- Pushes to fork `main` build an Actions artifact but never create a Release.
- Release publishing is manual and occurs only after the Windows build and offline provisioning smoke test pass.
- The build job retains `contents: read`; only the isolated release job receives `contents: write`.
- The Release contains the unsigned EXE and SHA-256 file and is neither draft nor prerelease.
- The first tag is `windows-offline-v0.17.0` and its title is `Hermes Desktop 0.17.0 – Windows x64 Offline`.

---

### Task 1: Add sync-triggered builds and isolated Release publishing

**Files:**
- Modify: `.github/workflows/build-windows-offline.yml`

**Interfaces:**
- Consumes: `workflow_dispatch.inputs.release_tag`, `workflow_dispatch.inputs.release_title`, and the `hermes-windows-x64-offline` artifact from the build job.
- Produces: automatic artifacts for `main` pushes and an optional GitHub Release containing `Hermes-Offline-*-windows-x64.exe` plus its `.sha256` file.

- [ ] **Step 1: Add manual inputs and the push trigger**

Add optional string inputs named `release_tag` and `release_title`, plus `push.branches: [main]`. An empty tag and title mean artifact-only mode.

- [ ] **Step 2: Add the isolated release job**

Add a Linux job with this gate and permission boundary:

```yaml
  release:
    if: >-
      github.event_name == 'workflow_dispatch' &&
      inputs.release_tag != '' &&
      inputs.release_title != ''
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: write
```

Download `hermes-windows-x64-offline` using the repository-pinned
`actions/download-artifact` v8.0.1 SHA, then call `gh release create` with
`--target "$GITHUB_SHA"`, the supplied title, the EXE, and checksum. The notes
must identify the installer as unsigned, Windows x64-only, and model-free.

- [ ] **Step 3: Validate the workflow before publishing**

Run:

```bash
.venv/bin/python -c 'from pathlib import Path; import yaml; yaml.safe_load(Path(".github/workflows/build-windows-offline.yml").read_text())'
git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 4: Commit and push**

```bash
git add .github/workflows/build-windows-offline.yml docs/superpowers/plans/2026-07-17-windows-offline-release.md
git commit -m "feat: publish Windows offline releases"
git push origin agent/windows-offline-installer
git push origin HEAD:main
```

- [ ] **Step 5: Trigger and verify the first Release**

Run:

```bash
gh workflow run build-windows-offline.yml \
  --repo ion-lgb/hermes-agent \
  --ref main \
  -f release_tag=windows-offline-v0.17.0 \
  -f 'release_title=Hermes Desktop 0.17.0 – Windows x64 Offline'
```

Wait for the workflow to complete successfully. Verify the Release and both
assets using `gh release view windows-offline-v0.17.0 --repo ion-lgb/hermes-agent`.

