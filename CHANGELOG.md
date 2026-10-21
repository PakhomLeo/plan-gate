# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org/).

## 1.0.0 – unreleased

First release of the merged project.

### Added

- One installer pair (`install.sh`, `install.ps1`) for two components: `skill` (any `SKILL.md` client, default Qoder) and `dsh` (DSH quick dev mode). Options: `--components`, `--skills-dir`, `--dsh-home`, `--uninstall`, `--migrate-legacy`, `--dry-run`.
- `.cpf-manifest` in each installed skill folder, so updates and uninstall touch only files the installer wrote.
- Upgrade path from the former installers: earlier installs are detected and left alone, or moved to `~/.code-project-flow-backups/<time>/` with `--migrate-legacy`. Nothing is deleted.
- `CPF_REF` / `CPF_REPO_URL` to pin the ref used by the one-line install.
- Tests: `tests/install-test.sh` (end-to-end, temp `HOME`) and `tests/parity-test.sh` (`install.sh` vs `install.ps1`, byte-identical results).
- English `README.md`, `README.zh-CN.md`, diagrams in `docs/assets/`, `CONTRIBUTING.md`, `SECURITY.md`, CI workflow.

### Changed

- One skill source (`SKILL.md`, `references/`, `docs/` layout). The DSH copy (project-root layout) is rendered at install time instead of kept as a second copy.
- The DSH skill copy now carries the latest workflow text (plain-language replies in the ASD-STE100 style).
- The skill is installed by copying instead of `git clone`; re-run the installer to update.
- Default Qoder folder detection is the same on both platforms; an existing install decides where updates go.

### Fixed

- `install.sh` (former `dsh-quick-dev`): a CRLF patch layer was written back with mixed line endings, and a CRLF layer holding only `[]` got the block appended after `[]`, which is not valid YAML. CRLF layers now keep CRLF and `[]` is replaced.
- `install.ps1` (former `dsh-quick-dev`): installing into a profile whose patch layer held only `[]` failed with "[System.Char] does not contain a method named 'Trim'".
- `install.ps1` no longer prints non-ASCII text, which Windows PowerShell 5.1 shows as mojibake, and no longer calls `exit` when piped through `iex`.
- The former `dsh-quick-dev` installer deleted the skill folder (`rm -rf`) on every install and uninstall, including files a user had added; the new installer removes only manifest files.

## History before 1.0.0

- `code-project-flow` (2026-09-28 – 2026-10-03, 4 commits): the workflow skill for Qoder; MIT.
- `dsh-quick-dev` (2026-09-29 – 2026-10-21, 3 commits): the DSH quick dev mode with a copy of the skill; MIT.

Their commit history is not carried into this repository.
