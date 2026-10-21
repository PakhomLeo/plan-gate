#!/usr/bin/env bash
# Runs install.sh and install.ps1 (PowerShell 7, `pwsh`) through the same
# scenarios on identical throwaway HOME folders and checks that both leave
# byte-identical trees and return the same exit codes.
#
#   bash tests/parity-test.sh            # needs pwsh on PATH, or PWSH=/path/to/pwsh
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PWSH="${PWSH:-pwsh}"
command -v "$PWSH" >/dev/null 2>&1 || { echo "pwsh not found; set PWSH=/path/to/pwsh" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
# shellcheck source=tests/legacy-fixtures.sh
. "$ROOT/tests/legacy-fixtures.sh"

# Same tree, ignoring the timestamped backup folder name. Patch layers embed
# the HOME path in the plugin URL, so they are compared by content below.
# pwsh keeps its own cache under HOME; that is not ours to compare. Git
# internals (index, logs) hold timestamps, so only the .git folder itself is.
snapshot() {
  local label
  label="$(printf '%s' "$1" | sed 's#^/##; s#[/\\: ]#_#g')"
  (cd "$1" && { find . \( -type f -o -type d \) -print; find . -type f -print0 | xargs -0 -r sha256sum; } \
     | grep -vE '^[0-9a-f]{64}  .*cordis\.patch\.yml$' | grep -v -e '^\./\.cache' -e '^\./\.local' -e ' \./\.cache/' -e ' \./\.local/' -e '/\.git/' \
     | sed -e 's#/\.plan-gate-backups/[0-9-]*#/.plan-gate-backups/STAMP#' -e "s#$label#HOME#g" | sort)
}

fixture() {
  local h="$1"
  rm -rf "$h"; mkdir -p "$h/.dsh/profiles/desktop" "$h/.dsh/profiles/web" "$h/.dsh/profiles/headless" "$h/.qoder/skills"
  printf '[]\n' > "$h/.dsh/profiles/desktop/cordis.patch.yml"
  mkdir -p "$h/.dsh/profiles/cli"; printf '[]\r\n' > "$h/.dsh/profiles/cli/cordis.patch.yml"
  printf '# user layer\n- insert:\n    - id: my-row\n      name: my-plugin' > "$h/.dsh/profiles/web/cordis.patch.yml"
  printf -- '- id: tool-web\r\n  disabled: true\r\n' > "$h/.dsh/profiles/headless/cordis.patch.yml"
  # A legacy copy made by the former Qoder installer (no manifest).
  mkdir -p "$h/.qoder/skills/code-project-flow/references"
  cp "$ROOT/SKILL.md" "$h/.qoder/skills/code-project-flow/"
  cp "$ROOT"/references/*.md "$h/.qoder/skills/code-project-flow/references/"
}

# Real installs made by the two former installers (see legacy-fixtures.sh).
legacy_fixture() {
  local h="$1"
  rm -rf "$h"; mkdir -p "$h/.dsh/profiles/desktop" "$h/.dsh/profiles/web" "$WORK/fx-$(basename "$h")"
  printf '[]\n' > "$h/.dsh/profiles/desktop/cordis.patch.yml"
  printf '# user layer\n- insert:\n    - id: my-row\n      name: my-plugin\n' > "$h/.dsh/profiles/web/cordis.patch.yml"
  legacy_code_project_flow "$WORK/fx-$(basename "$h")" "$h"
  legacy_dsh_quick_dev "$WORK/fx-$(basename "$h")" "$h"
  echo mine > "$h/.qoder-cn/skills/code-project-flow/my-notes.md"
  printf 'partial\n' > "$h/.dsh/profiles/web/cordis.patch.yml.dsh-quick-dev.tmp"
}

# Messages about former installs must match too.
notices() { grep -E '^(==> (Found|Note|  Files)|      )' "$1" | sed -e "s#$2#HOME#g" -e 's#-MigrateLegacy#--migrate-legacy#g'; }

# step NAME SH_ARGS -- PS_ARGS
step() {
  local name="$1"; shift
  local sh_args='' ps_args=''
  while [ "$1" != -- ]; do sh_args="$sh_args $1"; shift; done; shift
  ps_args="$*"
  set +e
  # shellcheck disable=SC2086
  # Each run starts in its own HOME, so a relative folder argument stays inside it.
  (cd "$WORK/sh" && HOME="$WORK/sh" bash "$ROOT/install.sh" $sh_args < /dev/null > "$WORK/sh.out" 2>&1); local rs=$?
  # shellcheck disable=SC2086
  (cd "$WORK/ps" && HOME="$WORK/ps" "$PWSH" -NoProfile -NonInteractive -File "$ROOT/install.ps1" $ps_args < /dev/null > "$WORK/ps.out" 2>&1); local rp=$?
  set -e
  # The plugin URL embeds the HOME path, which differs between the two runs.
  if [ "$rs" = "$rp" ] && diff <(snapshot "$WORK/sh" | sed "s#$WORK/sh#HOME#g") <(snapshot "$WORK/ps" | sed "s#$WORK/ps#HOME#g") > "$WORK/diff" \
     && diff <(notices "$WORK/sh.out" "$WORK/sh") <(notices "$WORK/ps.out" "$WORK/ps") >> "$WORK/diff" \
     && diff <(cd "$WORK/sh" && find . -name cordis.patch.yml -exec cat {} + | sed "s#$WORK/sh#HOME#g") \
             <(cd "$WORK/ps" && find . -name cordis.patch.yml -exec cat {} + | sed "s#$WORK/ps#HOME#g") >> "$WORK/diff"; then
    pass=$((pass + 1)); printf '  ok   %s (exit %s)\n' "$name" "$rs"
  else
    fail=$((fail + 1)); printf '  FAIL %s (sh exit %s, ps exit %s)\n' "$name" "$rs" "$rp"
    head -n 20 "$WORK/diff"; echo '--- sh'; cat "$WORK/sh.out"; echo '--- ps'; cat "$WORK/ps.out"
  fi
}

fixture "$WORK/sh"; fixture "$WORK/ps"
step 'dry run, all components'          --components all --dry-run -- -Components all -DryRun
step 'legacy skill blocks the skill'    --components skill -- -Components skill
step 'migrate legacy skill'             --components skill --migrate-legacy -- -Components skill -MigrateLegacy
step 'install dsh'                      --components dsh -- -Components dsh
step 're-install dsh (idempotent)'      --components dsh -- -Components dsh
step 'auto-detect re-install'           -- 
step 'uninstall dsh'                    --components dsh --uninstall -- -Components dsh -Uninstall
step 'uninstall skill'                  --components skill --uninstall -- -Components skill -Uninstall
for h in sh ps; do mkdir -p "$WORK/$h/.dsh/plugins"; echo '// edited' > "$WORK/$h/.dsh/plugins/quick-dev-plan-arm.mjs"; done
step 'modified plugin is kept'           --components dsh -- -Components dsh
step 'modified plugin migrated'          --components dsh --migrate-legacy -- -Components dsh -MigrateLegacy
step 'former -SkillsRoot / positional folder'  other/skills -- -SkillsRoot other/skills

legacy_fixture "$WORK/sh"; legacy_fixture "$WORK/ps"
step 'real former installs: dry run'     --dry-run -- -DryRun
step 'real former installs are blocked'  -- 
step 'real former installs migrated'     --migrate-legacy -- -MigrateLegacy
step 'after migration: plain update'     -- 
step 'uninstall all'                     --components all --uninstall -- -Components all -Uninstall

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
