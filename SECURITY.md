# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's private vulnerability reporting ("Security" tab → "Report a vulnerability") on this repository. Include the affected file, the steps to reproduce and the impact. You should get a first answer within a week.

## Scope

In scope:

- `install.sh` and `install.ps1`: writing outside the documented folders, overwriting or deleting user files, privilege escalation, command injection through paths or environment variables.
- `dsh/plugin/quick-dev-plan-arm.mjs` and `dsh/preset/quick-dev.patch.yml`: anything that widens what the agent may do beyond DSH's standard mode, or approves a plan without the user.
- `SKILL.md` and `references/`: instructions that make an agent skip user confirmation.

Out of scope: DSH, Qoder or other agent clients themselves (report those upstream), and the documented risk of the one-line `curl | bash` / `irm | iex` install, which runs unverified code by design. Use a checkout or pin `CPF_REF` instead.

## Supported versions

Only the latest release receives fixes.
