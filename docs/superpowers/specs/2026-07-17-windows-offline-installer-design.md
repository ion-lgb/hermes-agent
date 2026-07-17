# Windows Offline Installer Design

## Goal

Build a Windows x64 NSIS installer in GitHub Actions that installs the Hermes
framework and desktop application without network access. The installer does
not include a model or model server.

## Distribution boundary

The installer contains the Electron desktop application, the Hermes source
snapshot, a relocatable CPython 3.11 distribution, an offline Python
wheelhouse for the curated `[all]` dependency set, portable Node.js 22,
PortableGit, the root Node dependencies, and agent-browser's Chrome for
Testing runtime. Optional
providers excluded from `[all]` remain unavailable until installed separately.

The installed layout matches the existing Windows bootstrap contract under
`%LOCALAPPDATA%\hermes`:

```text
%LOCALAPPDATA%\hermes\
  hermes-agent\
    venv\
    node_modules\
    .hermes-bootstrap-complete
  python\
  node\
  git\
  agent-browser\
```

## Build architecture

The manually triggered GitHub Actions workflow runs on `windows-latest` and:

1. installs the pinned build toolchain;
2. exports the tracked repository into an offline payload without `.git`;
3. downloads managed CPython into the payload with `uv python install`;
4. builds a Windows wheelhouse from `.[all]`;
5. stages portable Node.js and PortableGit;
6. installs root Node dependencies and Chrome for Testing into the payload;
7. builds the Electron desktop with an offline-specific electron-builder
   configuration; and
8. uploads the NSIS EXE and SHA-256 file as workflow artifacts.

The NSIS `customInstall` macro invokes the bundled PowerShell provisioning
script after Electron files are installed. A non-zero provisioning exit aborts
the installation. The payload is removed from the Electron installation after
successful provisioning to avoid retaining a second copy.

## Offline provisioning

The provisioning script accepts explicit payload, Hermes home, and browser
runtime directories. It reads the source commit from the validated payload
manifest.
It validates every required payload component before mutating the destination,
copies the source and portable runtimes, creates a fresh venv at its final path,
and installs with `--no-index --find-links`. It never invokes `uv`, Git, npm,
winget, or a URL on the target computer.

The installer preserves an existing `config.yaml`, changing only
`security.allow_lazy_installs` to `false`. It preserves `.env` while setting
the bundled browser home and executable path. It writes the existing schema-1
bootstrap marker using the build commit so the Electron resolver uses the
installed venv and does not start the online bootstrap path.

## Runtime behavior

The source snapshot deliberately excludes `.git`; desktop update checks then
report that self-update is unsupported without contacting a remote. Lazy Python
dependency installation is disabled. Chrome for Testing is installed under
Hermes home and selected explicitly, so browser tools do not download a browser
on first use.

Cloud providers, web search, external browsing, OAuth, messaging services, and
other network-backed tools still require network access by definition. Users
configure a model provider after installation; no model choice is imposed by
this package.

## Verification

The repository tests cover offline configuration mutation and the Windows
managed-Node PATH contract. The workflow smoke-tests the generated payload by
running the network-free provisioning script in a temporary Hermes home, then
imports `hermes_cli` from the created venv. The workflow also verifies that the
final NSIS EXE and SHA-256 file exist before upload.
