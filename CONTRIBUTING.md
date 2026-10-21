# Contributing

Thanks for helping. This project is small on purpose: one skill, four templates, one DSH preset and plugin, and one installer for two platforms. Changes that keep it that way are the easiest to accept.

## Before you start

- Open an issue first for anything larger than a typo, so we can agree on the plan. (Yes, the same rule the workflow enforces.)
- The workflow text (`SKILL.md`, `references/`, the DSH preset guidance) is Chinese. English templates are welcome as a separate, clearly named addition; do not mix languages inside one file.
- `references/AGENTS.md` is a template that users own once copied. Keep it generic: no project-, company- or machine-specific content.

## Where things live

| Change | Edit | Also update |
| --- | --- | --- |
| Workflow rules or templates | `SKILL.md`, `references/*.md` (always with `docs/` paths) | Both READMEs if behaviour changes |
| DSH mode | `dsh/preset/quick-dev.patch.yml`, `dsh/plugin/quick-dev-plan-arm.mjs` | If the plugin content changes, add the **old** file's sha256 (LF line endings) to `KNOWN_PLUGIN_SHA256` in **both** installers, so upgrades recognise it |
| Installer | `install.sh` **and** `install.ps1` | `tests/install-test.sh`, both READMEs |
| Files the installer ships | `SKILL_FILES` in both installers | The manifest logic handles removal of dropped files |
| Diagrams | `scripts/make_diagrams.py`, then `python3 scripts/make_diagrams.py docs/assets` | Keep the shared style block |
| Release | `VERSION`, `CHANGELOG.md` (replace `Unreleased` with the date) | Push tag `vX.Y.Z`; the release workflow builds the assets and `SHA256SUMS` with `scripts/make-release.sh`. Never edit `SHA256SUMS` by hand |

Do not hand-edit a rendered DSH copy: the installer derives the project-root layout from the source by replacing `docs/MAP.md`, `docs/HARNESS.md` and `docs/TASK.md` with bare names.

## Installer rules

These are the project's promises to users. A pull request that breaks one will not be merged:

1. No `sudo` or elevation.
2. Overwrite or remove only what the installer wrote (manifest, known plugin hash, the one preset block).
3. Never delete user files. Earlier installs move to `~/.code-project-flow-backups/<time>/` only with `--migrate-legacy` or an interactive "y".
4. A patch layer is byte-for-byte unchanged after install then uninstall, for LF and CRLF files.
5. `install.sh` and `install.ps1` behave the same. `install.sh` stays bash 3.2 compatible (macOS). `install.ps1` stays ASCII and Windows PowerShell 5.1 compatible, and never calls `exit` when piped through `iex`.
6. Console output is English.

## Checks

Run these before opening a pull request:

```bash
shellcheck install.sh scripts/*.sh tests/*.sh
bash tests/install-test.sh
bash tests/parity-test.sh        # PowerShell 7: https://aka.ms/powershell
bash tests/release-test.sh
```

Optional: `Invoke-ScriptAnalyzer -Path install.ps1` (PSScriptAnalyzer). `PSAvoidUsingWriteHost` is expected for a console installer.

All tests use throwaway `HOME` folders and never touch your real configuration.

## Commits and pull requests

- One topic per pull request; describe what users will notice.
- Line endings are LF (see `.gitattributes`).
- By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
