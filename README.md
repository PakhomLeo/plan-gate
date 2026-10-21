# code-project-flow

English | [简体中文](README.zh-CN.md)

**A plan-first workflow for AI coding agents.** It does not change *how* the agent writes code. It controls *when the agent may start*: the agent writes a short plan, stops, waits for your approval, builds, and runs its checks once at the end.

The project ships two components from one repository and one installer:

| Component | For | What you get |
| --- | --- | --- |
| `skill` | Qoder, and any agent client that reads the `SKILL.md` format | The workflow skill: `SKILL.md` plus four document templates |
| `dsh` | [DSH (DeepSeek Harness)](https://github.com/deepseek-ai/deepseek-harness) | A "quick dev" agent mode next to the built-in standard mode: the same skill, a small plugin that opens plan mode when a plan is due, and the mode declaration |

> This project merges two earlier repositories, `dsh-quick-dev` and `code-project-flow`. See [History](#history) and [Upgrading from the earlier repositories](#upgrading-from-the-earlier-repositories).

---

## Contents

- [Why](#why)
- [How it works](#how-it-works)
- [Install](#install)
- [Upgrading from the earlier repositories](#upgrading-from-the-earlier-repositories)
- [The DSH quick dev mode](#the-dsh-quick-dev-mode)
- [Security and permissions](#security-and-permissions)
- [Customising](#customising)
- [Repository layout](#repository-layout)
- [Development and tests](#development-and-tests)
- [History](#history)
- [Contributing](#contributing) · [License](#license)

---

## Why

AI-assisted coding tends to fail in four ways:

| Failure | What it looks like |
| --- | --- |
| Writes before agreeing | Requirements are still fuzzy, twenty files already changed |
| Drifts further each round | The same spot breaks again, so it grows another branch, wrapper or flag |
| Context blowup | Every new session re-reads the whole repository, mostly detail this task never touches |
| Fake green | Tests mock around the real path; it passes locally and breaks when it ships |

The workflow answers them with **four documents, five phases and four overriding principles**, and turns "may I start?" into an explicit approval step instead of a vague "go ahead" in the chat.

---

## How it works

### Five phases

![Five phases: read, write brief, confirm, build, close out](docs/assets/workflow-phases.svg)

1. **Read** – the rules and design documents first. If the design document does not exist, the agent drafts it from the *actual* shape of the code, not an ideal one, and leaves the structure and the two flows for you to review.
2. **Write the brief** – `TASK.md`, in plain language (the ASD-STE100 simplified-technical style: short sentences, one word for one thing, active voice), with exactly seven sections: why; how, down to functions and paths (files not listed must not be touched); what it touches; what not to do on the side; conflicts with the design document; details that need your sign-off; acceptance boundary. **Then it stops.**
3. **Confirm** – until you explicitly say go, nothing changes. "Keep refining" sends your feedback back to the brief.
4. **Build** – if the brief lists a conflict with the design document, that sentence goes into the design document first. No tests and no harness runs while building.
5. **Close out** – one run only: check the round against the brief's acceptance boundary, then run every registered harness with real data, no fake mocks. A failure is fixed in the code; registered checks are never loosened or deleted to get a green result. The agent then *proposes* write-backs to the design and harness documents, with before and after sentences. They are written only if you agree, and a "no" is never asked twice. Finally `TASK.md` is deleted.

### Four documents

![The four documents and where they live](docs/assets/four-documents.svg)

| | File | Who writes it | What it owns |
| --- | --- | --- | --- |
| Doc 1 | `AGENTS.md` | **You only** | Agent rules, the four overriding principles, who owns what |
| Doc 2 | `MAP.md` | Agent proposes, you approve | Design: feature choices, project structure, user flow, data flow (eight fixed sections) |
| Doc 3 | `HARNESS.md` | Agent proposes, you approve | Registered regression loops ("harnesses"); their code lives in `harness/` |
| Doc 4 | `TASK.md` | Agent writes, you confirm, deleted at close-out | This round only, down to functions and paths (seven fixed sections) |

Where the documents live depends on the component:

- **`skill`**: `AGENTS.md` in the project root, the other three under `docs/` (`docs/MAP.md`, `docs/HARNESS.md`, `docs/TASK.md`).
- **`dsh`**: all four in the project root. DSH auto-loads instruction files by bare file name while walking up from the working directory, so a file in a subfolder would never load. The installer renders the skill for this layout; the source is the same.

The documents are also the workflow's state. A new session reads Docs 1–3 and knows which step it is on, without chat memory. Templates: [`references/`](references/).

### Four overriding principles

They live in Doc 1 and win over any other instruction:

- **No patches** – fix the place that produced the error; no extra branch, wrapper, compatibility layer, flag or special case next to it.
- **Self-explanatory code** – names and structure say what the code does; comments only hold what a reader would guess wrong (why, who calls it, what it guarantees).
- **No residue** – unused functions, files, flags, commented-out code, stale harnesses and the task brief are removed at close-out.
- **Deployment parity** – the path that works locally is the path that ships; no per-machine special cases, no fake data.

### Language

`SKILL.md`, the four templates and the DSH mode's built-in guidance are **Chinese**. This README explains them in English. The agent reads Chinese rules and fills Chinese templates; your code and comments stay in your project's language. Pull requests adding English templates are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)).

---

## Install

![Components and install targets](docs/assets/install-components.svg)

Requirements: `bash` (macOS, Linux, WSL, Git Bash) or PowerShell 5.1+ on Windows. `git` is needed only for the piped one-line install. For the `dsh` component, DSH must have been started at least once, so that `profiles/` exists.

### From a checkout (recommended)

```bash
git clone https://github.com/PakhomLeo/code-project-flow.git
cd code-project-flow
./install.sh --dry-run      # see what would change
./install.sh                # install the auto-detected components
```

```powershell
git clone https://github.com/PakhomLeo/code-project-flow.git
cd code-project-flow
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`-ExecutionPolicy Bypass` applies to this one process only; it does not change your machine's policy.

### Options

| `install.sh` | `install.ps1` | Meaning |
| --- | --- | --- |
| `--components skill,dsh` | `-Components skill,dsh` | What to install: `skill`, `dsh` or `all`. Default: auto-detect (see below) |
| `--skills-dir DIR` | `-SkillsDir DIR` (alias `-SkillsRoot`) | Skills folder for `skill`. Default: `~/.qoder-cn/skills`, or `~/.qoder/skills` |
| `--dsh-home DIR` | `-DshHome DIR` | DSH home for `dsh`. Default: `$DSH_HOME`, then `~/.dsh` |
| `--uninstall` | `-Uninstall` | Remove what the installer installed |
| `--migrate-legacy` | `-MigrateLegacy` | Move installs made by the earlier installers to a backup folder, then continue |
| `--dry-run` | `-DryRun` | Print planned changes, change nothing |

Auto-detect picks `skill` when a Qoder skills folder exists or `--skills-dir` is given, and `dsh` when `$DSH_HOME/profiles` exists or `--dsh-home` is given. With neither, it installs `skill` into `~/.qoder-cn/skills`. If the skill is already installed under `~/.qoder/skills`, updates go there.

Exit codes: `0` done, `1` error, `2` bad arguments, `3` finished but skipped a step (for example an earlier install that needs `--migrate-legacy`).

### Other agent clients

Any client that loads `SKILL.md` skills from a folder can use the `skill` component:

```bash
./install.sh --components skill --skills-dir /path/to/your/client/skills
```

Start a new agent session afterwards; skills load at session start.

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/PakhomLeo/code-project-flow/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/PakhomLeo/code-project-flow/main/install.ps1 | iex
```

This runs a script from the network without a checksum, and the script then clones the default branch. Prefer the checkout above. To pin a release, set `CPF_REF` (for example `CPF_REF=v1.0.0`); `CPF_REPO_URL` points at a fork. Pass options after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/PakhomLeo/code-project-flow/main/install.sh | CPF_REF=v1.0.0 bash -s -- --components dsh
```

### Make it the default (Qoder)

Installing only makes the skill available. To route every coding task through it, add this to your global `~/.qoder-cn/AGENTS.md` (or a project's `AGENTS.md`). Keep it verbatim; it matches the skill's Chinese trigger description:

```markdown
凡写代码、改代码、把功能落到仓库的任务，默认使用 skill code-project-flow。
开工先写 docs/TASK.md 并停下等确认。
```

Without that line, the skill fires on words such as 开工 (start work), 收工 (close out), MAP, 当次说明 (task brief) or harness, or when you ask for it by name. The installer never edits your `AGENTS.md`.

### Update and uninstall

Update: pull the checkout and run the installer again. It rewrites only the files listed in its `.cpf-manifest` and removes files that an earlier version shipped and this one does not.

```bash
./install.sh --uninstall                  # or: --components dsh --uninstall
```

```powershell
.\install.ps1 -Uninstall
```

Uninstall removes the files in the manifest, the plugin if its content matches a shipped version, and the preset block. A patch layer is then byte-for-byte what it was before. Files you added to the skill folder stay, and so does the folder.

---

## Upgrading from the earlier repositories

| You installed with | What the new installer finds | What to do |
| --- | --- | --- |
| `code-project-flow` `install.sh`/`install.ps1` (a `git clone` in `~/.qoder-cn/skills/code-project-flow` or `~/.qoder/skills/code-project-flow`) | A skill folder without `.cpf-manifest` | Run `./install.sh --migrate-legacy` once. The old checkout, including its `.git`, moves to `~/.code-project-flow-backups/<time>/` |
| `dsh-quick-dev` `install.sh`/`install.ps1` | A skill copy without manifest in `$DSH_HOME/skills/`, the same plugin file, and the same preset block | Run `./install.sh --components dsh --migrate-legacy` once. The plugin and preset block are recognised and replaced in place |
| Manual copy of the skill folder | A skill folder without manifest | Same as the first row |

Without `--migrate-legacy` (or a "y" at the interactive prompt), an earlier install is left untouched and the installer exits with code `3`. Nothing is ever deleted: delete the backup folder yourself when you no longer need it. The installer also prints a note when it sees an earlier install in a place this run does not manage.

What changed for existing users:

- The skill is now **copied**, not cloned. `git pull` inside the skills folder is no longer the update path; run the installer again.
- The `dsh` skill copy now uses the newest workflow text (plain-language replies in the ASD-STE100 style), which `dsh-quick-dev` already used in its mode guidance.
- Positional `./install.sh /path/to/skills` still works and prints a deprecation note; use `--skills-dir`.

---

## The DSH quick dev mode

The `dsh` component adds a mode named 快速开发模式 ("quick dev"), shown second in the new-session picker. After installing, **restart DSH and start a blank session**; DSH only switches modes on a session without history.

What the installer writes into `$DSH_HOME`:

| Where | What |
| --- | --- |
| `skills/code-project-flow/` | The workflow skill, rendered for the project-root document layout |
| `plugins/quick-dev-plan-arm.mjs` | Opens plan mode when a plan is due |
| `profiles/*/cordis.patch.yml` | One top-level `- insert:` entry with id `preset-quick-dev`, in every existing profile |

The mode declaration ([`dsh/preset/quick-dev.patch.yml`](dsh/preset/quick-dev.patch.yml)) is a copy of DSH's standard mode plugin list with four changes: a persona suffix asking for plain-language replies, auto-loaded instruction files widened to `AGENTS.md`, `CLAUDE.md`, `MAP.md`, `HARNESS.md`, `TASK.md` with a 200 KB budget, a plan-mode prompt that explains the workflow, and one extra plugin row. The other rows were copied unchanged from standard mode when the preset was written, so the tool list is the same.

![When the plugin opens plan mode](docs/assets/dsh-plan-arm.svg)

The plugin ([`dsh/plugin/quick-dev-plan-arm.mjs`](dsh/plugin/quick-dev-plan-arm.mjs)) exists because a new DSH session starts outside plan mode and the model has no tool to enter it. It turns plan mode on for root agents when the working directory has `AGENTS.md` and no `TASK.md`, and again after a round's `TASK.md` disappears. It skips subagents, adds no tools, blocks no tool call, and only logs a warning if anything fails.

Known boundaries (by design):

- Only blank sessions can switch modes (a DSH rule).
- DSH lists the mode under "custom" in settings; the picker order comes from `order: 1.5`.
- Modes do not inherit. When DSH updates its standard mode, this copy does not follow; re-check `dsh/preset/quick-dev.patch.yml` against new DSH releases.
- The workflow is guidance, not a fence. It never removes tools per phase, because changing the tool table would invalidate the prompt cache.
- DSH source code is not modified.

---

## Security and permissions

**Installers** (`install.sh`, `install.ps1`):

- Never use `sudo` or elevation. They write only to the chosen skills folder, the DSH home, and the backup folder (only with `--migrate-legacy`).
- Overwrite or remove only what they installed: files listed in `.cpf-manifest`, a plugin whose hash matches a shipped version, and the one preset block. Anything else is reported and skipped.
- The one-line install downloads and runs code without a checksum. Use a checkout, or pin `CPF_REF`.

**What the agent gets:**

- The skill is text only. Its front matter has `name` and `description`; it declares no tools, permissions or auto-approval.
- The DSH mode uses the same tool rows as DSH's standard mode (shell, file system, web fetch, subagents and so on). It adds no tools, sets no sandbox or approval policy, and keeps DSH's own approval behaviour. In the preset, the plugin-manager tool, the external `codex` and `claude-code` subagent rows and `tool-ralph` are disabled.
- The plugin only makes the agent *more* restricted (it turns plan mode on). Approving a plan is always your action.

Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

---

## Customising

`references/AGENTS.md` is the template meant for you to edit; put your copy in the project root. The agent must not change it.

> **Note:** the template is written for **exploratory projects**. It tells the agent not to add security checks, permissions, retries or caching to temporary components yet. For production code, replace that paragraph with your own bar before you use it.

`SKILL.md` is editable too, but it is the workflow itself; changes alter how the five phases run. Edit the source in this repository (with `docs/` paths) and reinstall; the installer renders the DSH layout.

Good fit: exploratory projects where blocks may be thrown away; long-lived repositories that suffer from drift; wanting a plan before code. Poor fit: throwaway scripts, and requirements you expect the agent to discover by writing.

---

## Repository layout

```
.
├── SKILL.md                     # skill entry point: the five-phase rules (Chinese)
├── references/                  # the four document templates (Chinese)
│   ├── AGENTS.md  MAP.md  HARNESS.md  TASK.md
├── dsh/
│   ├── preset/quick-dev.patch.yml   # DSH mode declaration (profile patch layer block)
│   └── plugin/quick-dev-plan-arm.mjs
├── install.sh  install.ps1      # one installer, two platforms, same behaviour
├── tests/
│   ├── install-test.sh          # end-to-end test of install.sh in a temp HOME
│   └── parity-test.sh           # install.sh vs install.ps1, byte-identical results
├── scripts/                     # diagram generator and PNG preview export
├── docs/assets/                 # SVG diagrams (light and dark aware)
├── VERSION  CHANGELOG.md  LICENSE  CONTRIBUTING.md  SECURITY.md
└── README.md  README.zh-CN.md
```

When this repository is cloned straight into a skills folder (the earlier manual method), `SKILL.md` and `references/` are still at its root, so it keeps working. The installer is the supported path.

---

## Development and tests

```bash
shellcheck install.sh tests/*.sh
bash tests/install-test.sh                 # install.sh, every case in a throwaway HOME
bash tests/parity-test.sh                  # needs PowerShell 7 (pwsh)
```

The tests never touch your real home folder. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## History

Version 1.0.0 merges two repositories by the same author:

- **code-project-flow** (2026-09-28 – 2026-10-03): the workflow skill for Qoder, with `docs/` document layout and a `git clone` installer.
- **dsh-quick-dev** (2026-09-29 – 2026-10-21): the DSH quick dev mode, with a copy of the skill in the project-root layout, the plan-arm plugin and the preset.

The two skill copies are now one source. See [CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 PakhomLeo
