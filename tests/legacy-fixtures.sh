# shellcheck shell=bash
# Sourced by the tests. Recreates REAL installs made by the two former
# installers, offline, from git bundles of the former repositories:
#   tests/fixtures/legacy/code-project-flow.bundle  (main = f42f945, last commit)
#   tests/fixtures/legacy/dsh-quick-dev.bundle      (main = cde8672, last commit)
# The former scripts run unmodified. code-project-flow's install.sh clones
# https://github.com/PakhomLeo/code-project-flow.git; a git url.insteadOf
# setting (environment only) points that URL at a local copy of the bundle, so
# the result, including .git/config, is what a user got from GitHub.

LEGACY_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/legacy" && pwd)"

# legacy_code_project_flow WORKDIR HOME_DIR: the former Qoder skill install.
legacy_code_project_flow() {
  local work="$1" home="$2"
  rm -rf "$work/cpf-src" "$work/cpf.git"
  git -c init.defaultBranch=main clone -q "$LEGACY_FIXTURES/code-project-flow.bundle" "$work/cpf-src"
  git -c init.defaultBranch=main clone -q --bare "$LEGACY_FIXTURES/code-project-flow.bundle" "$work/cpf.git"
  mkdir -p "$home/.qoder-cn/skills"
  HOME="$home" GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$work/cpf.git.insteadOf" \
    GIT_CONFIG_VALUE_0='https://github.com/PakhomLeo/code-project-flow.git' \
    bash "$work/cpf-src/install.sh" > "$work/legacy-cpf.out" 2>&1
}

# legacy_dsh_quick_dev WORKDIR HOME_DIR: the former DSH mode install into
# HOME_DIR/.dsh, which must already have profiles/*/cordis.patch.yml.
legacy_dsh_quick_dev() {
  local work="$1" home="$2"
  rm -rf "$work/dsh-src"
  git -c init.defaultBranch=main clone -q "$LEGACY_FIXTURES/dsh-quick-dev.bundle" "$work/dsh-src"
  (unset DSH_HOME; HOME="$home" bash "$work/dsh-src/install.sh") > "$work/legacy-dsh.out" 2>&1
}
