# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's private vulnerability reporting ("Security" tab → "Report a vulnerability") on this repository. Include the affected file, the steps to reproduce and the impact. You should get a first answer within a week.

## Scope

In scope:

- `install.sh` and `install.ps1`: writing outside the documented folders, overwriting or deleting user files, privilege escalation, command injection through paths or environment variables.
- `dsh/plugin/quick-dev-plan-arm.mjs` and `dsh/preset/quick-dev.patch.yml`: anything that widens what the agent may do beyond DSH's standard mode, or approves a plan without the user.
- `SKILL.md` and `references/`: instructions that make an agent skip user confirmation.

- `scripts/make-release.sh` and `.github/workflows/release.yml`: a release whose `SHA256SUMS` does not match its assets.

Out of scope: DSH, Qoder or other agent clients themselves (report those upstream), and piping `install.sh` or `install.ps1` from the network straight into a shell, which skips verification and is not a documented install method. Clone the repository, or download a release archive and check it against the release's `SHA256SUMS` first (see the README).

## Supported versions

Only the latest release receives fixes.
