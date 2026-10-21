# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Documentation

- README (English and Chinese): a real terminal screenshot of `./install.sh` (v1.0.0, temporary `HOME`) in the Install section, `docs/assets/install-terminal.png`.

## [1.0.0] - 2026-10-21

First release of **plan-gate** (https://github.com/PakhomLeo/plan-gate), the merged project. The installed skill keeps the name `code-project-flow`. Tag: `v1.0.0`.

### Added

- One installer pair (`install.sh`, `install.ps1`) for two components: `skill` (any `SKILL.md` client, default Qoder) and `dsh` (DSH quick dev mode). Options: `--components`, `--skills-dir`, `--dsh-home`, `--uninstall`, `--migrate-legacy`, `--dry-run`.
- `.plan-gate-manifest` in each installed skill folder, so updates and uninstall touch only files the installer wrote.
- Migration from the former `dsh-quick-dev` and `code-project-flow` installers: their installs are recognised by location, origin and content (git checkout of `PakhomLeo/code-project-flow`, `dsh-quick-dev` skill copy, the shipped plugin, the `preset-quick-dev` block, a leftover `cordis.patch.yml.dsh-quick-dev.tmp`). They are left alone, or moved to `~/.plan-gate-backups/<time>/` with `--migrate-legacy`. Nothing is deleted.
- Release assets with checksums: `scripts/make-release.sh` builds `plan-gate-vX.Y.Z.tar.gz`/`.zip`, `install.sh`, `install.ps1` and `SHA256SUMS`; `.github/workflows/release.yml` publishes them when a `v*` tag is pushed. The README's one-line install downloads, verifies, then runs.
- `PLAN_GATE_REF` / `PLAN_GATE_REPO_URL` for the (undocumented, unverified) piped mode of the installers.
- Tests: `tests/install-test.sh` (end-to-end, temp `HOME`), `tests/parity-test.sh` (`install.sh` vs `install.ps1`, byte-identical results) and `tests/release-test.sh` (release assets, checksum verification, tampered download). The migration cases run the former installers, unmodified and offline, from git bundles in `tests/fixtures/legacy/`.
- English `README.md`, `README.zh-CN.md`, diagrams in `docs/assets/`, `CONTRIBUTING.md`, `SECURITY.md`, CI workflow.

### Changed

- Project and repository name: plan-gate. The skill name, the DSH preset id, the plugin file name and the mode name are unchanged, so existing `AGENTS.md` lines and installs keep working.
- One skill source (`SKILL.md`, `references/`, `docs/` layout). The DSH copy (project-root layout) is rendered at install time instead of kept as a second copy.
- The DSH skill copy now carries the latest workflow text (plain-language replies in the ASD-STE100 style).
- `SKILL.md` and the `AGENTS.md` template: "add no security checks" is now "add no extra security layer during development; never remove or bypass existing authentication, permission checks or input validation; validate external input as usual".
- DSH preset: the plan-mode prompt restates every rule of DSH's standard plan-mode prompt (checked against deepseek-ai/deepseek-harness `687f282`), which the earlier preset had replaced.
- The README recommends clone-then-run; the one-line install is an alternative that verifies a release archive first.
- The skill is installed by copying instead of `git clone`; re-run the installer to update.
- Default Qoder folder detection is the same on both platforms; an existing install decides where updates go.

### Fixed

- `install.sh` (former `dsh-quick-dev`): a CRLF patch layer was written back with mixed line endings, and a CRLF layer holding only `[]` got the block appended after `[]`, which is not valid YAML. CRLF layers now keep CRLF and `[]` is replaced.
- `install.ps1` (former `dsh-quick-dev`): installing into a profile whose patch layer held only `[]` failed with "[System.Char] does not contain a method named 'Trim'".
- `install.ps1` no longer prints non-ASCII text, which Windows PowerShell 5.1 shows as mojibake, and no longer calls `exit` when piped through `iex`.
- The former `dsh-quick-dev` installer deleted the skill folder (`rm -rf`) on every install and uninstall, including files a user had added; the new installer removes only manifest files.

## History before 1.0.0

- `PakhomLeo/code-project-flow` (2026-09-28 – 2026-10-03, 4 commits): the workflow skill for Qoder; MIT.
- `PakhomLeo/dsh-quick-dev` (2026-09-29 – 2026-10-21, 3 commits): the DSH quick dev mode with a copy of the skill; MIT.

Their commit history is not carried into this repository.
