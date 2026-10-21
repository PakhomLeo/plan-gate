#!/usr/bin/env bash
# End-to-end test for install.sh. Every case runs against a throwaway HOME,
# so nothing outside a temp folder is touched.
#
#   bash tests/install-test.sh
#
# Optional: python3 with PyYAML validates the patched cordis.patch.yml files.
#
# check() evaluates its second argument later, so the single quotes are intended.
# shellcheck disable=SC2016,SC2034
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/install.sh"
# shellcheck source=tests/legacy-fixtures.sh
. "$ROOT/tests/legacy-fixtures.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

fresh_home() {
  HOME="$WORK/home-$1"; export HOME
  unset DSH_HOME || true
  mkdir -p "$HOME"
}
run() { bash "$INSTALL" "$@" > "$WORK/out" 2>&1; }
run_rc() { set +e; bash "$INSTALL" "$@" > "$WORK/out" 2>&1; rc=$?; set -e; }
tree_sum() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1; }

make_dsh() {
  local d="$HOME/.dsh/profiles"
  mkdir -p "$d/desktop" "$d/web" "$d/headless" "$d/cli"
  printf '[]\r\n' > "$d/cli/cordis.patch.yml"
  printf '[]\n' > "$d/desktop/cordis.patch.yml"
  # Existing user rows, a comment and no trailing newline.
  printf '# user layer\n- insert:\n    - id: my-row\n      name: my-plugin' > "$d/web/cordis.patch.yml"
  # CRLF, as written on Windows.
  printf -- '- id: tool-web\r\n  disabled: true\r\n' > "$d/headless/cordis.patch.yml"
  cp -R "$d" "$WORK/profiles-orig"
}

yaml_ok() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$@" <<'PY' || return 1
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
class L(yaml.SafeLoader): pass
L.add_multi_constructor('', lambda loader, suffix, node: None)
for p in sys.argv[1:]:
    data = yaml.load(open(p, encoding='utf-8'), Loader=L)
    assert isinstance(data, list), p
PY
}

echo '1. skill component, fresh HOME'
fresh_home skill
run
S="$HOME/.qoder-cn/skills/code-project-flow"
check 'installs into ~/.qoder-cn/skills by default' '[ -f "$S/SKILL.md" ] && [ -f "$S/references/TASK.md" ] && [ -f "$S/LICENSE" ]'
check 'writes a manifest' '[ -f "$S/.plan-gate-manifest" ]'
check 'docs layout keeps docs/TASK.md' 'cmp -s "$S/SKILL.md" "$ROOT/SKILL.md"'
sum1="$(tree_sum "$S")"; run
check 're-run is idempotent' '[ "$sum1" = "$(tree_sum "$S")" ]'
echo note > "$S/my-notes.md"
printf 'references/OLD.md\n' >> "$S/.plan-gate-manifest"; echo old > "$S/references/OLD.md"
run
check 'update removes a stale file it shipped' '[ ! -e "$S/references/OLD.md" ]'
check 'update keeps a user file' '[ -f "$S/my-notes.md" ]'
run --uninstall
check 'uninstall removes shipped files' '[ ! -e "$S/SKILL.md" ] && [ ! -e "$S/.plan-gate-manifest" ]'
check 'uninstall keeps the user file and its folder' '[ -f "$S/my-notes.md" ]'

echo '2. skill component, --skills-dir and deprecated positional folder'
fresh_home custom
run --skills-dir "$HOME/agent/skills"
check '--skills-dir is honoured' '[ -f "$HOME/agent/skills/code-project-flow/SKILL.md" ]'
run "$HOME/other/skills"
check 'bare folder argument still works' '[ -f "$HOME/other/skills/code-project-flow/SKILL.md" ]'
check 'and prints a deprecation note' 'grep -q deprecated "$WORK/out"'

echo '3. dsh component'
fresh_home dsh
make_dsh
run --components dsh
D="$HOME/.dsh"
check 'auto-detect would also pick dsh' 'bash "$INSTALL" --dry-run | grep -q "auto-detected): dsh"'
check 'plugin installed' 'cmp -s "$D/plugins/quick-dev-plan-arm.mjs" "$ROOT/dsh/plugin/quick-dev-plan-arm.mjs"'
check 'skill uses the project-root layout' '! grep -q "docs/TASK.md" "$D/skills/code-project-flow/SKILL.md" && grep -q "\`TASK.md\`" "$D/skills/code-project-flow/SKILL.md"'
check 'one preset block per profile' '[ "$(cat "$D"/profiles/*/cordis.patch.yml | grep -c "id: preset-quick-dev")" = 4 ]'
check 'placeholder filled with a file:// URL' '! grep -q __QUICK_DEV_PLUGIN_URL__ "$D"/profiles/*/cordis.patch.yml && grep -q "file://$D/plugins/quick-dev-plan-arm.mjs" "$D/profiles/web/cordis.patch.yml"'
check 'empty [] layer replaced, not appended (LF and CRLF)' '! grep -qx "\[\]" "$D/profiles/desktop/cordis.patch.yml" && ! grep -q "^\[\]" "$D/profiles/cli/cordis.patch.yml"'
check 'user rows kept' 'grep -q "id: my-row" "$D/profiles/web/cordis.patch.yml"'
check 'CRLF layer stays CRLF' '[ "$(grep -c $'"'"'\r$'"'"' "$D/profiles/headless/cordis.patch.yml")" = "$(wc -l < "$D/profiles/headless/cordis.patch.yml")" ]'
check 'DSH copy keeps the security wording of the source' 'for f in SKILL.md references/AGENTS.md; do grep -q "已有的认证、权限和输入校验不得删除，不得绕过。涉及外部输入的地方照常校验。" "$D/skills/code-project-flow/$f" || exit 1; done'
check 'no copy still says "add no security checks"' '! grep -rqE "不加安全检查" "$ROOT/SKILL.md" "$ROOT/references" "$D/skills/code-project-flow"'
check 'preset keeps the standard plan-mode rules' 'grep -q "对话里的同意不算批准" "$D/profiles/web/cordis.patch.yml" && grep -q "不提交，也不用别的方式执行计划" "$D/profiles/web/cordis.patch.yml" && grep -q "评审通道不可用或被中止" "$D/profiles/web/cordis.patch.yml"'
check 'patched layers are valid YAML' 'yaml_ok "$D"/profiles/*/cordis.patch.yml'
sumd="$(tree_sum "$D")"; run --components dsh
check 're-run is idempotent (byte-identical)' '[ "$sumd" = "$(tree_sum "$D")" ]'
run --components dsh --uninstall
check 'uninstall restores every layer byte-for-byte' 'diff -r "$WORK/profiles-orig" "$D/profiles" >/dev/null'
check 'uninstall removes plugin and skill' '[ ! -e "$D/plugins/quick-dev-plan-arm.mjs" ] && [ ! -e "$D/skills/code-project-flow" ]'

echo '4. legacy installs are never touched without consent'
fresh_home legacy
L="$HOME/.qoder/skills/code-project-flow"
mkdir -p "$L/references"; cp "$ROOT/SKILL.md" "$L/"; cp "$ROOT"/references/*.md "$L/references/"
git -C "$L" init -q; git -C "$L" add -A; git -C "$L" -c user.name=t -c user.email=t@example.invalid commit -qm legacy
before="$(tree_sum "$L")"
run_rc < /dev/null
check 'update target follows the existing install (~/.qoder)' 'grep -q "$L" "$WORK/out"'
check 'without --migrate-legacy: exit 3' '[ "$rc" = 3 ]'
check 'without --migrate-legacy: untouched' '[ "$before" = "$(tree_sum "$L")" ]'
run --migrate-legacy
B="$(find "$HOME/.plan-gate-backups" -mindepth 2 -maxdepth 2 -type d | head -n 1)"
check 'with --migrate-legacy: old copy moved to backup, git history intact' '[ -d "$B/.git" ] && [ "$before" = "$(tree_sum "$B")" ]'
check 'with --migrate-legacy: new install has a manifest' '[ -f "$L/.plan-gate-manifest" ] && [ ! -e "$L/.git" ]'

echo '5. foreign folder and modified plugin'
fresh_home foreign
F="$HOME/.qoder-cn/skills/code-project-flow"; mkdir -p "$F"; echo mine > "$F/notes.txt"
run_rc --components skill
check 'foreign folder: exit 3 and untouched' '[ "$rc" = 3 ] && [ "$(ls "$F")" = notes.txt ]'
make_dsh
mkdir -p "$HOME/.dsh/plugins"; echo '// edited' > "$HOME/.dsh/plugins/quick-dev-plan-arm.mjs"
run_rc --components dsh < /dev/null
check 'modified plugin: exit 3 and kept' '[ "$rc" = 3 ] && grep -q edited "$HOME/.dsh/plugins/quick-dev-plan-arm.mjs"'
check 'modified plugin: preset not written' '! grep -q preset-quick-dev "$HOME/.dsh/profiles/web/cordis.patch.yml"'
run --components dsh --migrate-legacy
check 'modified plugin: replaced after --migrate-legacy, old one in backup' 'cmp -s "$HOME/.dsh/plugins/quick-dev-plan-arm.mjs" "$ROOT/dsh/plugin/quick-dev-plan-arm.mjs" && grep -rq edited "$HOME/.plan-gate-backups"'

echo '6. dry run changes nothing'
fresh_home dry
make_dsh
b="$(tree_sum "$HOME")"
run --components all --dry-run
check 'no file changed' '[ "$b" = "$(tree_sum "$HOME")" ]'
check 'prints planned writes' 'grep -q "\[dry-run\] write" "$WORK/out"'

echo '7. piped install fetches the repository'
if git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null; then
  fresh_home pipe
  PLAN_GATE_REPO_URL="file://$ROOT" bash -s -- --components skill < "$INSTALL" > "$WORK/out" 2>&1
  check 'installs from a fresh clone' 'grep -q Fetching "$WORK/out" && [ -f "$HOME/.qoder-cn/skills/code-project-flow/SKILL.md" ]'
else
  echo '  skip (no commit yet)'
fi

echo '8. upgrade a real install made by the former code-project-flow installer'
fresh_home legacy-cpf
legacy_code_project_flow "$WORK" "$HOME"
L="$HOME/.qoder-cn/skills/code-project-flow"
check 'fixture: the former installer cloned PakhomLeo/code-project-flow at f42f945' 'grep -q "url = https://github.com/PakhomLeo/code-project-flow.git" "$L/.git/config" && [ "$(git -C "$L" rev-parse HEAD)" = f42f9455da0ce90c571c7f25161544193e920ddb ] && [ -f "$L/install.sh" ] && [ -f "$L/README.en.md" ]'
echo mine > "$L/my-notes.md"
before="$(tree_sum "$L")"
run_rc < /dev/null
check 'recognised as a code-project-flow git checkout' 'grep -q "Found a code-project-flow git checkout made by a former installer: $L" "$WORK/out"'
check 'lists only the file the former installer did not write' '[ "$(grep -c "^      " "$WORK/out")" = 1 ] && grep -q "^      my-notes.md" "$WORK/out"'
check 'without --migrate-legacy: exit 3 and untouched' '[ "$rc" = 3 ] && [ "$before" = "$(tree_sum "$L")" ]'
run --migrate-legacy
B="$(find "$HOME/.plan-gate-backups" -mindepth 2 -maxdepth 2 -type d | head -n 1)"
check 'with --migrate-legacy: whole checkout (.git, user file) is in the backup, unchanged' '[ "$before" = "$(tree_sum "$B")" ] && git -C "$B" rev-parse -q --verify HEAD >/dev/null'
check 'with --migrate-legacy: new copy-based install in the same folder' '[ -f "$L/.plan-gate-manifest" ] && [ ! -e "$L/.git" ] && [ ! -e "$L/install.sh" ] && cmp -s "$L/SKILL.md" "$ROOT/SKILL.md"'
run_rc < /dev/null
check 'next run is a plain update (exit 0, no legacy notice)' '[ "$rc" = 0 ] && ! grep -q "former installer" "$WORK/out"'

echo '9. upgrade a real install made by the former dsh-quick-dev installer'
fresh_home legacy-dsh
mkdir -p "$HOME/.dsh/profiles/desktop" "$HOME/.dsh/profiles/web"
printf '[]\n' > "$HOME/.dsh/profiles/desktop/cordis.patch.yml"
printf '# user layer\n- insert:\n    - id: my-row\n      name: my-plugin\n' > "$HOME/.dsh/profiles/web/cordis.patch.yml"
rm -rf "$WORK/profiles-orig"; cp -R "$HOME/.dsh/profiles" "$WORK/profiles-orig"
legacy_dsh_quick_dev "$WORK" "$HOME"
D="$HOME/.dsh"
check 'fixture: the former installer wrote skill, plugin and one block per layer' '[ -f "$D/skills/code-project-flow/SKILL.md" ] && [ ! -e "$D/skills/code-project-flow/LICENSE" ] && [ -f "$D/plugins/quick-dev-plan-arm.mjs" ] && [ "$(cat "$D"/profiles/*/cordis.patch.yml | grep -c "id: preset-quick-dev")" = 2 ]'
# Simulated: what an interrupted former run leaves next to a layer.
printf 'partial\n' > "$D/profiles/web/cordis.patch.yml.dsh-quick-dev.tmp"
before="$(tree_sum "$D")"
run_rc --components dsh < /dev/null
check 'recognised as a dsh-quick-dev copy with no extra files' 'grep -q "Found a dsh-quick-dev copy made by a former installer: $D/skills/code-project-flow" "$WORK/out" && ! grep -q "^      " "$WORK/out"'
check 'leftover .dsh-quick-dev.tmp is reported' 'grep -q "leftover of an interrupted dsh-quick-dev run" "$WORK/out"'
check 'without --migrate-legacy: exit 3 and nothing changed' '[ "$rc" = 3 ] && [ "$before" = "$(tree_sum "$D")" ]'
run --components dsh --migrate-legacy
B="$(find "$HOME/.plan-gate-backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
check 'with --migrate-legacy: old skill copy and leftover moved to the backup' '[ -f "$(find "$B" -path "*code-project-flow/SKILL.md" | head -n 1)" ] && [ -n "$(find "$B" -name "*cordis.patch.yml.dsh-quick-dev.tmp")" ] && [ ! -e "$D/profiles/web/cordis.patch.yml.dsh-quick-dev.tmp" ]'
check 'plugin recognised as a shipped version: replaced, not backed up' '[ -z "$(find "$B" -name quick-dev-plan-arm.mjs)" ] && cmp -s "$D/plugins/quick-dev-plan-arm.mjs" "$ROOT/dsh/plugin/quick-dev-plan-arm.mjs"'
check 'preset block replaced in place: still one per layer' 'grep -q "Replaced the existing preset" "$WORK/out" && [ "$(cat "$D"/profiles/*/cordis.patch.yml | grep -c "id: preset-quick-dev")" = 2 ] && grep -q "对话里的同意不算批准" "$D/profiles/web/cordis.patch.yml"'
check 'new skill copy has a manifest and the root layout' '[ -f "$D/skills/code-project-flow/.plan-gate-manifest" ] && ! grep -q "docs/TASK.md" "$D/skills/code-project-flow/SKILL.md"'
run --components dsh --uninstall
check 'uninstall: layers byte-identical to before the former install' 'diff -r "$WORK/profiles-orig" "$D/profiles" >/dev/null'

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
