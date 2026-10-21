#!/usr/bin/env bash
# Builds release assets from the current working tree in a throwaway repo,
# then runs the README's "download, verify, run" commands against them:
# sha256sum -c, shasum -a 256 -c, PowerShell Get-FileHash (when pwsh exists),
# a tampered download that must be rejected, and the extracted installer.
#
#   bash tests/release-test.sh
#
# check() evaluates its second argument later, so the single quotes are intended.
# shellcheck disable=SC2016,SC2034
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PWSH="${PWSH:-pwsh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

V="v$(tr -d ' \r\n' < "$ROOT/VERSION")"
NAME="code-project-flow-$V"

# A copy of the working tree (tracked + new, not ignored) as one tagged commit.
mkdir "$WORK/repo"
(cd "$ROOT" && git ls-files -z -co --exclude-standard | xargs -0 -I{} cp --parents {} "$WORK/repo/") 2>/dev/null \
  || (cd "$ROOT" && git ls-files -co --exclude-standard | while IFS= read -r f; do mkdir -p "$WORK/repo/$(dirname "$f")"; cp -p "$f" "$WORK/repo/$f"; done)
git -C "$WORK/repo" init -q
git -C "$WORK/repo" add -A
git -C "$WORK/repo" -c user.name=test -c user.email=test@example.invalid commit -qm release-test
git -C "$WORK/repo" tag "$V"

echo "1. build $V"
bash "$WORK/repo/scripts/make-release.sh" "$V" "$WORK/dist" > "$WORK/build.out"
check 'all assets present' '[ -f "$WORK/dist/$NAME.tar.gz" ] && [ -f "$WORK/dist/$NAME.zip" ] && [ -f "$WORK/dist/install.sh" ] && [ -f "$WORK/dist/install.ps1" ] && [ -f "$WORK/dist/SHA256SUMS" ]'
check 'SHA256SUMS lists four files' '[ "$(wc -l < "$WORK/dist/SHA256SUMS")" = 4 ]'
check 'a tag that does not match VERSION is refused' '! bash "$WORK/repo/scripts/make-release.sh" HEAD "$WORK/x" >/dev/null 2>&1'

echo '2. download, verify, run (README commands, file:// instead of https://)'
B="file://$WORK/dist"
mkdir "$WORK/u1" && cd "$WORK/u1"
export HOME="$WORK/home1"; mkdir -p "$HOME"
curl -fsSLO "$B/$NAME.tar.gz" && curl -fsSLO "$B/SHA256SUMS"
check 'sha256sum -c passes' 'grep " $NAME.tar.gz\$" SHA256SUMS | sha256sum -c - >/dev/null'
if command -v shasum >/dev/null 2>&1; then
  check 'shasum -a 256 -c passes' 'grep " $NAME.tar.gz\$" SHA256SUMS | shasum -a 256 -c - >/dev/null'
fi
tar xzf "$NAME.tar.gz"
bash "./$NAME/install.sh" --components skill > "$WORK/inst.out" 2>&1
check 'extracted installer runs without fetching anything' '! grep -q Fetching "$WORK/inst.out" && [ -f "$HOME/.qoder-cn/skills/code-project-flow/.cpf-manifest" ]'
check 'installers in the archive match the separate assets' 'cmp -s "$NAME/install.sh" "$WORK/dist/install.sh" && cmp -s "$NAME/install.ps1" "$WORK/dist/install.ps1"'

echo '3. a tampered download is rejected'
mkdir "$WORK/u2" && cd "$WORK/u2"
cp "$WORK/dist/SHA256SUMS" .; cp "$WORK/dist/$NAME.tar.gz" .; printf 'x' >> "$NAME.tar.gz"
check 'sha256sum -c fails' '! grep " $NAME.tar.gz\$" SHA256SUMS | sha256sum -c - >/dev/null 2>&1'

echo '4. Windows path: Get-FileHash, Expand-Archive, install.ps1'
if command -v "$PWSH" >/dev/null 2>&1; then
  mkdir "$WORK/u3" && cd "$WORK/u3"
  cp "$WORK/dist/$NAME.zip" "$WORK/dist/SHA256SUMS" .
  HOME="$WORK/home3" "$PWSH" -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'; \$f = '$NAME.zip'
    \$want = (((Get-Content SHA256SUMS) -match \"  \$([regex]::Escape(\$f))\`\$\") -split '\s+')[0]
    if ((Get-FileHash \$f -Algorithm SHA256).Hash -ne \$want) { throw 'checksum mismatch' }
    Expand-Archive \$f -DestinationPath .
    & \"./$NAME/install.ps1\" -Components skill
  " > "$WORK/ps.out" 2>&1 && rc=0 || rc=$?
  check 'Get-FileHash matches and install.ps1 runs' '[ "$rc" = 0 ] && [ -f "$WORK/home3/.qoder-cn/skills/code-project-flow/.cpf-manifest" ]'
  printf 'x' >> "$NAME.zip"
  HOME="$WORK/home3" "$PWSH" -NoProfile -NonInteractive -Command "
    \$f = '$NAME.zip'
    \$want = (((Get-Content SHA256SUMS) -match \"  \$([regex]::Escape(\$f))\`\$\") -split '\s+')[0]
    if ((Get-FileHash \$f -Algorithm SHA256).Hash -ne \$want) { exit 9 }
  " > /dev/null 2>&1 && rc=0 || rc=$?
  check 'Get-FileHash rejects a tampered zip' '[ "$rc" = 9 ]'
else
  echo '  skip (pwsh not found)'
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
