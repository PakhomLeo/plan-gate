#!/usr/bin/env bash
#
# Install, update or uninstall code-project-flow.
#
# Components (pick with --components, default: auto-detect):
#   skill  The workflow skill (SKILL.md + references/) for any agent client that
#          reads the SKILL.md format. Default target: the Qoder skills folder.
#          Documents live under docs/ in the consuming project.
#   dsh    The DSH "quick dev" mode: the same skill rendered for the project-root
#          document layout, the plan-arm plugin, and a preset block in every
#          profile's cordis.patch.yml.
#
# Safety rules this script keeps:
#   - It never uses sudo and never writes outside the chosen skills folder, the
#     DSH home and (only with --migrate-legacy) the backup folder.
#   - It only overwrites or removes files it installed itself: those listed in
#     the .cpf-manifest file it leaves in each skill folder, a plugin file whose
#     content matches a shipped version, and the one preset block it inserts.
#   - An older install (from the former code-project-flow or dsh-quick-dev
#     installers) has no manifest. It is left alone unless you pass
#     --migrate-legacy or answer "y" at the prompt; then it is moved into
#     ~/.code-project-flow-backups/<timestamp>/, never deleted.
#
# Console messages are English on purpose: this script also runs under
# non-UTF-8 locales where translated output would turn into mojibake.
#
# bash 3.2 (macOS) compatible: no arrays under set -u, no associative arrays.
set -eu

CPF_REPO_URL="${CPF_REPO_URL:-https://github.com/PakhomLeo/code-project-flow.git}"
CPF_REF="${CPF_REF:-}"
SKILL_NAME='code-project-flow'
PLUGIN_FILE='quick-dev-plan-arm.mjs'
PLACEHOLDER='__QUICK_DEV_PLUGIN_URL__'
PRESET_ID='preset-quick-dev'
MANIFEST='.cpf-manifest'
# sha256 of every plugin version ever shipped (LF line endings). A plugin file
# with one of these hashes is ours and may be replaced or removed.
# dsh-quick-dev 2026-09-29..2026-10-21 shipped one plugin version.
KNOWN_PLUGIN_SHA256='414735eda972288f2f7d58a8cf9986290f1697f1578d8ad1e8699c317f337826'
SKILL_FILES='SKILL.md
references/AGENTS.md
references/HARNESS.md
references/MAP.md
references/TASK.md
LICENSE'

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

  --components LIST   Comma-separated: skill, dsh, all. Default: auto-detect.
  --skills-dir DIR    Skills folder for the "skill" component.
                      Default: ~/.qoder-cn/skills or ~/.qoder/skills.
  --dsh-home DIR      DSH home for the "dsh" component. Default: $DSH_HOME, then ~/.dsh.
  --uninstall         Remove what this script installed.
  --migrate-legacy    Move installs made by the former installers into a backup
                      folder, then continue. Nothing is deleted.
  --dry-run           Print what would change and change nothing.
  -h, --help          Show this help.

Environment (only used when the script is not run from a checkout):
  CPF_REPO_URL        Repository to fetch.  CPF_REF  Tag or branch to fetch.
USAGE
}

components=''
skills_dir=''
dsh_home=''
uninstall=0
migrate=0
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --components)
      [ $# -ge 2 ] || { echo '--components needs a value' >&2; exit 2; }
      components="$2"; shift ;;
    --skills-dir)
      [ $# -ge 2 ] || { echo '--skills-dir needs a directory' >&2; exit 2; }
      skills_dir="$2"; shift ;;
    --dsh-home)
      [ $# -ge 2 ] || { echo '--dsh-home needs a directory' >&2; exit 2; }
      dsh_home="$2"; shift ;;
    --uninstall) uninstall=1 ;;
    --migrate-legacy) migrate=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      # The former code-project-flow installer took the skills folder as $1.
      if [ -z "$skills_dir" ]; then
        skills_dir="$1"
        echo "Note: a bare folder argument is deprecated, use --skills-dir $1" >&2
      else
        echo "Unexpected argument: $1" >&2; exit 2
      fi ;;
  esac
  shift
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.code-project-flow-backups/$STAMP"
skipped=0

say() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
act() {
  # act DESCRIPTION -- COMMAND...: run COMMAND, or only print it under --dry-run.
  local what="$1"; shift; shift
  if [ "$dry_run" -eq 1 ]; then
    if [ -n "$what" ]; then printf '[dry-run] %s\n' "$what"; fi
  else
    "$@"
  fi
}

sha256_lf() {
  # Hash with CR removed, so a CRLF checkout of a shipped file still matches.
  if command -v sha256sum >/dev/null 2>&1; then
    tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1
  else
    tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

# --- where the files come from -------------------------------------------

checkout_root() {
  local self="${BASH_SOURCE[0]:-}"
  if [ -n "$self" ] && [ -f "$self" ]; then
    local dir
    dir="$(cd "$(dirname "$self")" && pwd)"
    if [ -f "$dir/SKILL.md" ] && [ -f "$dir/dsh/plugin/$PLUGIN_FILE" ]; then printf '%s' "$dir"; fi
  fi
}

temporary=''
cleanup() { if [ -n "$temporary" ]; then rm -rf "$temporary"; fi; }
trap cleanup EXIT

source_root="$(checkout_root)"
if [ -z "$source_root" ] && [ "$uninstall" -eq 0 ]; then
  command -v git >/dev/null 2>&1 || { echo 'git is required but was not found on PATH.' >&2; exit 1; }
  temporary="$(mktemp -d)"
  say "Fetching $CPF_REPO_URL ${CPF_REF:+(ref $CPF_REF)}"
  if [ -n "$CPF_REF" ]; then
    git clone --quiet --depth 1 --branch "$CPF_REF" "$CPF_REPO_URL" "$temporary/src"
  else
    git clone --quiet --depth 1 "$CPF_REPO_URL" "$temporary/src"
  fi
  source_root="$temporary/src"
fi
VERSION='unknown'
if [ -n "$source_root" ] && [ -f "$source_root/VERSION" ]; then VERSION="$(tr -d ' \r\n' < "$source_root/VERSION")"; fi

# --- targets ---------------------------------------------------------------

if [ -n "$dsh_home" ]; then DSH_ROOT="$dsh_home"
elif [ -n "${DSH_HOME:-}" ]; then DSH_ROOT="$DSH_HOME"
else DSH_ROOT="$HOME/.dsh"; fi

QODER_CN="$HOME/.qoder-cn/skills"
QODER_GLOBAL="$HOME/.qoder/skills"

resolve_skills_root() {
  if [ -n "$skills_dir" ]; then printf '%s' "$skills_dir"; return; fi
  local root
  # An existing install wins, so an update lands where the old copy is.
  for root in "$QODER_CN" "$QODER_GLOBAL"; do
    if [ -e "$root/$SKILL_NAME" ]; then printf '%s' "$root"; return; fi
  done
  for root in "$QODER_CN" "$QODER_GLOBAL"; do
    if [ -d "$root" ]; then printf '%s' "$root"; return; fi
  done
  printf '%s' "$HOME/.qoder-cn/skills"
}
SKILLS_ROOT="$(resolve_skills_root)"

if [ -z "$components" ]; then
  if [ -n "$skills_dir" ] || [ -d "$QODER_CN" ] || [ -d "$QODER_GLOBAL" ]; then components='skill'; fi
  if [ -n "$dsh_home" ] || [ -d "$DSH_ROOT/profiles" ]; then components="${components:+$components,}dsh"; fi
  [ -n "$components" ] || components='skill'
  say "Components (auto-detected): $components"
fi
want_skill=0; want_dsh=0
old_ifs="$IFS"; IFS=','
for c in $components; do
  case "$c" in
    skill) want_skill=1 ;;
    dsh) want_dsh=1 ;;
    all) want_skill=1; want_dsh=1 ;;
    '') ;;
    *) IFS="$old_ifs"; echo "Unknown component: $c (use skill, dsh or all)" >&2; exit 2 ;;
  esac
done
IFS="$old_ifs"

# --- skill folders ---------------------------------------------------------

# absent | owned (has our manifest) | legacy (former installers) | foreign
skill_state() {
  local dir="$1"
  if [ ! -e "$dir" ]; then echo absent
  elif [ -f "$dir/$MANIFEST" ]; then echo owned
  elif [ -f "$dir/SKILL.md" ] && grep -q "^name: ${SKILL_NAME}[[:space:]]*\$" "$dir/SKILL.md"; then echo legacy
  else echo foreign; fi
}

backup() {
  # Move a legacy install out of the way. Never deletes.
  local path="$1" label="$2"
  local dest="$BACKUP_ROOT/$label"
  act "move $path to $dest" -- mkdir -p "$BACKUP_ROOT"
  act "" -- mv "$path" "$dest"
  say "Moved legacy install $path to $dest (delete it yourself once you no longer need it)"
}

confirm_legacy() {
  # Returns 0 when the user agreed to move a legacy install aside.
  local path="$1"
  if [ "$migrate" -eq 1 ]; then return 0; fi
  if [ "$dry_run" -eq 0 ] && [ -t 0 ]; then
    printf 'Found an install made by a former installer: %s\nMove it to %s and continue? [y/N] ' "$path" "$BACKUP_ROOT" >&2
    local answer=''
    read -r answer || answer=''
    case "$answer" in y|Y|yes|YES) return 0 ;; esac
  fi
  return 1
}

legacy_label() { printf '%s' "$1" | sed 's#^/##; s#[/\\: ]#_#g'; }

render() {
  # render SRC DEST LAYOUT: the source uses docs/MAP.md etc. The DSH mode
  # auto-loads documents by bare file name from the project root, so the
  # "root" layout drops the docs/ prefix.
  local src="$1" dest="$2" layout="$3"
  if [ "$layout" = root ]; then
    sed -e 's#docs/MAP\.md#MAP.md#g' -e 's#docs/HARNESS\.md#HARNESS.md#g' -e 's#docs/TASK\.md#TASK.md#g' "$src" > "$dest"
  else
    cp "$src" "$dest"
  fi
}

# Sets installed=1 on success. Returns 0 on a skip too: a function called from
# `if` or `||` runs with set -e switched off, so failures must stay fatal by
# calling it as a plain statement.
install_skill() {
  local dir="$1" layout="$2" state
  installed=0
  state="$(skill_state "$dir")"
  case "$state" in
    foreign)
      warn "$dir exists and is not a code-project-flow install. Rename or remove it yourself, then run again."
      skipped=1; return 0 ;;
    legacy)
      if confirm_legacy "$dir"; then backup "$dir" "$(legacy_label "$dir")"; state=absent
      else
        warn "Legacy install left untouched: $dir. Re-run with --migrate-legacy to move it to a backup folder and install."
        skipped=1; return 0
      fi ;;
  esac
  local old=''
  if [ "$state" = owned ]; then old="$(grep -v '^#' "$dir/$MANIFEST" || true)"; fi
  local f
  for f in $SKILL_FILES; do
    act "write $dir/$f" -- mkdir -p "$(dirname "$dir/$f")"
    act "" -- render "$source_root/$f" "$dir/$f" "$layout"
  done
  # Files an older version of this installer wrote and this version no longer ships.
  for f in $old; do
    if ! printf '%s\n' "$SKILL_FILES" | grep -qxF -- "$f" && [ -f "$dir/$f" ]; then
      act "remove stale $dir/$f" -- rm -f "$dir/$f"
    fi
  done
  if [ "$dry_run" -eq 0 ]; then
    { printf '# code-project-flow %s layout=%s. Files below were written by install.sh/install.ps1.\n' "$VERSION" "$layout"
      printf '%s\n' "$SKILL_FILES"; } > "$dir/$MANIFEST"
  fi
  installed=1
  say "Installed skill ($layout layout) $dir"
}

uninstall_skill() {
  local dir="$1" state
  state="$(skill_state "$dir")"
  case "$state" in
    absent) say "Nothing at $dir" ;;
    foreign) warn "$dir is not a code-project-flow install; left untouched." ;;
    legacy)
      if confirm_legacy "$dir"; then backup "$dir" "$(legacy_label "$dir")"
      else warn "Legacy install left untouched: $dir. Re-run with --migrate-legacy to move it to a backup folder."; skipped=1; fi ;;
    owned)
      local f
      for f in $(grep -v '^#' "$dir/$MANIFEST" || true); do
        if [ -f "$dir/$f" ]; then act "remove $dir/$f" -- rm -f "$dir/$f"; fi
      done
      act "remove $dir/$MANIFEST" -- rm -f "$dir/$MANIFEST"
      act "" -- rmdir "$dir/references" 2>/dev/null || true
      act "" -- rmdir "$dir" 2>/dev/null || true
      if [ "$dry_run" -eq 0 ] && [ -e "$dir" ]; then
        warn "Kept $dir: it still holds files this script did not install."
      fi
      say "Removed skill $dir" ;;
  esac
}

note_other_legacy() {
  # Point at old copies this run does not handle, without touching them.
  local dir
  for dir in "$QODER_CN" "$QODER_GLOBAL" "$DSH_ROOT/skills"; do
    dir="$dir/$SKILL_NAME"
    case ",$handled," in *",$dir,"*) continue ;; esac
    if [ "$(skill_state "$dir")" = legacy ]; then
      say "Note: an older install also exists at $dir (not changed). Use --components/--skills-dir to manage it."
    fi
  done
}

# --- DSH -------------------------------------------------------------------

# Splice the preset block into one patch layer, or cut it out again, leaving
# every other line and the trailing-newline state exactly as they were. The
# block comes in as the first file; awk keys off FILENAME, not NR==FNR, because
# uninstall passes an empty block file. The block is found as YAML structure
# (the top-level `- insert:` entry that inserts preset-quick-dev), never by
# comment markers: a trailing marker comment would land inside the last
# plugin row's text.
patch_layer() {
  local mode="$1" patch="$2" block="$3" url="$4"
  local trailing=0
  if [ -s "$patch" ] && [ -z "$(tail -c 1 "$patch")" ]; then trailing=1; fi
  local work="$patch.cpf.tmp"
  awk -v mode="$mode" -v preset="$PRESET_ID" -v placeholder="$PLACEHOLDER" \
      -v url="$url" -v trailing="$trailing" -v blockpath="$block" '
    function fill(s,   p) {
      p = index(s, placeholder)
      if (p == 0) return s
      return substr(s, 1, p - 1) url substr(s, p + length(placeholder))
    }
    function find_entry(   i, j, k) {
      es = 0; ee = 0
      for (i = 1; i <= n; i++) {
        if (line[i] != "- insert:") continue
        j = i + 1
        while (j <= n && substr(line[j], 1, 2) != "- ") j++
        for (k = i + 1; k < j; k++) {
          if (line[k] ~ ("^[ \\t]*- id: " preset "[ \\t]*$")) { es = i; ee = j; return }
        }
        i = j - 1
      }
    }
    function count_significant(limit,   i, t, sig) {
      sig = 0
      for (i = 1; i <= limit; i++) {
        t = out[i]; gsub(/^[ \t]+/, "", t); gsub(/[ \t]+$/, "", t)
        if (t == "" || substr(t, 1, 1) == "#") continue
        sig++
      }
      return sig
    }
    # CRLF layers (written on Windows) are matched without the CR and written
    # back with it, so a shared DSH home stays byte-identical on round trips.
    FILENAME == blockpath { sub(/\r$/, ""); block[++bn] = $0; next }
    { if (sub(/\r$/, "")) crlf = 1; line[++n] = $0 }
    END {
      find_entry()
      if (mode == "remove") {
        if (es == 0) {
          for (i = 1; i <= n; i++) out[++on] = line[i]
        } else {
          for (i = 1; i < es; i++) out[++on] = line[i]
          for (i = ee; i <= n; i++) out[++on] = line[i]
          if (count_significant(on) == 0) out[++on] = "[]"
        }
      } else if (es > 0) {
        for (i = 1; i < es; i++) out[++on] = line[i]
        for (i = 1; i <= bn; i++) out[++on] = fill(block[i])
        for (i = ee; i <= n; i++) out[++on] = line[i]
      } else {
        sig = 0; idx = 0
        for (i = 1; i <= n; i++) {
          t = line[i]; gsub(/^[ \t]+/, "", t); gsub(/[ \t]+$/, "", t)
          if (t == "" || substr(t, 1, 1) == "#") continue
          sig++; idx = i
        }
        if (sig == 1 && line[idx] ~ /^[ \t]*\[\][ \t]*$/) {
          for (i = 1; i < idx; i++) out[++on] = line[i]
          for (i = 1; i <= bn; i++) out[++on] = fill(block[i])
          for (i = idx + 1; i <= n; i++) out[++on] = line[i]
        } else {
          for (i = 1; i <= n; i++) out[++on] = line[i]
          for (i = 1; i <= bn; i++) out[++on] = fill(block[i])
        }
      }
      eol = crlf ? "\r\n" : "\n"
      for (i = 1; i <= on; i++) printf "%s%s", out[i], (i < on ? eol : (trailing + 0 ? eol : ""))
    }
  ' "$block" "$patch" > "$work"
  mv "$work" "$patch"
}

dsh_patches() {
  local patch
  for patch in "$DSH_ROOT"/profiles/*/cordis.patch.yml; do
    if [ -f "$patch" ]; then printf '%s\n' "$patch"; fi
  done
}

plugin_is_ours() {
  local sum known
  sum="$(sha256_lf "$1")"
  [ -n "$source_root" ] && [ "$sum" = "$(sha256_lf "$source_root/dsh/plugin/$PLUGIN_FILE")" ] && return 0
  for known in $KNOWN_PLUGIN_SHA256; do [ "$sum" = "$known" ] && return 0; done
  return 1
}

do_dsh() {
  if [ ! -d "$DSH_ROOT/profiles" ]; then
    warn "Not a DSH home directory (no profiles folder): $DSH_ROOT. Start DSH once first, or pass --dsh-home."
    skipped=1; return 0
  fi
  local patches
  patches="$(dsh_patches)"
  if [ -z "$patches" ]; then
    warn "No profile patch layer under $DSH_ROOT/profiles. Start DSH once first."
    skipped=1; return 0
  fi
  local plugin="$DSH_ROOT/plugins/$PLUGIN_FILE"
  local skill="$DSH_ROOT/skills/$SKILL_NAME"
  local url
  url="$(printf '%s' "file://$plugin" | sed 's/ /%20/g')"
  handled="$handled,$skill"

  if [ "$uninstall" -eq 1 ]; then
    printf '%s\n' "$patches" | while IFS= read -r patch; do
      if grep -qF -- "- id: $PRESET_ID" "$patch"; then
        act "remove preset block from $patch" -- patch_layer remove "$patch" /dev/null "$url"
        say "Removed preset block from $patch"
      fi
    done
    if [ -f "$plugin" ]; then
      if plugin_is_ours "$plugin"; then act "remove $plugin" -- rm -f "$plugin"; say "Removed $plugin"
      elif confirm_legacy "$plugin"; then backup "$plugin" "$(legacy_label "$plugin")"
      else warn "Kept $plugin: its content differs from every shipped version. Re-run with --migrate-legacy to move it to a backup folder."; skipped=1; fi
    fi
    uninstall_skill "$skill"
    say 'DSH: restart DSH for the mode to disappear from the picker.'
    return 0
  fi

  # Skill first: if it is a legacy copy the user declines to move, stop before
  # the preset points DSH at a half-updated install.
  install_skill "$skill" root
  [ "$installed" -eq 1 ] || return 0

  if [ -f "$plugin" ] && ! plugin_is_ours "$plugin"; then
    if confirm_legacy "$plugin"; then backup "$plugin" "$(legacy_label "$plugin")"
    else warn "Kept $plugin: its content differs from every shipped version. Re-run with --migrate-legacy to replace it (the old file goes to a backup folder)."; skipped=1; return 0; fi
  fi
  act "write $plugin" -- mkdir -p "$DSH_ROOT/plugins"
  act "" -- cp "$source_root/dsh/plugin/$PLUGIN_FILE" "$plugin"
  say "Installed $plugin"

  printf '%s\n' "$patches" | while IFS= read -r patch; do
    act "write preset block into $patch" -- patch_layer write "$patch" "$source_root/dsh/preset/quick-dev.patch.yml" "$url"
    say "Wrote preset 'quick-dev' into $patch"
  done
  say 'DSH: restart DSH, start a new blank session and pick the quick dev mode (second in the list).'
}

# --- run -------------------------------------------------------------------

handled=''
installed=0
if [ "$dry_run" -eq 1 ]; then say 'Dry run: nothing will be changed.'; fi
if [ "$want_skill" -eq 1 ]; then
  handled="$handled,$SKILLS_ROOT/$SKILL_NAME"
  if [ "$uninstall" -eq 1 ]; then
    uninstall_skill "$SKILLS_ROOT/$SKILL_NAME"
  else
    act "create $SKILLS_ROOT" -- mkdir -p "$SKILLS_ROOT"
    install_skill "$SKILLS_ROOT/$SKILL_NAME" docs
    if [ "$installed" -eq 1 ]; then say 'Skill: start a new agent session for it to take effect.'; fi
  fi
fi
if [ "$want_dsh" -eq 1 ]; then do_dsh; fi
note_other_legacy

if [ "$skipped" -ne 0 ]; then
  echo 'Finished with skipped steps (see warnings above).' >&2
  exit 3
fi
echo 'Done.'
