#!/usr/bin/env bash
# Build the release assets for one tag into an output folder:
#
#   plan-gate-vX.Y.Z.tar.gz   git archive of the tag (Linux / macOS)
#   plan-gate-vX.Y.Z.zip      git archive of the tag (Windows)
#   install.sh  install.ps1   the installers from the same tag
#   SHA256SUMS                sha256 of every file above
#
# Usage: scripts/make-release.sh vX.Y.Z [OUTDIR]     (default OUTDIR: dist)
#
# The tag must match VERSION. The release workflow runs this script and
# uploads OUTDIR as release assets; SHA256SUMS is not committed to the repo.
set -eu

tag="${1:-}"
out="${2:-dist}"
[ -n "$tag" ] || { echo "Usage: $0 vX.Y.Z [OUTDIR]" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
git rev-parse --verify -q "$tag^{commit}" >/dev/null || { echo "No such tag or commit: $tag" >&2; exit 1; }
version="$(git show "$tag:VERSION" | tr -d ' \r\n')"
[ "v$version" = "$tag" ] || { echo "Tag $tag does not match VERSION $version" >&2; exit 1; }

name="plan-gate-$tag"
mkdir -p "$out"
git archive --format=tar.gz --prefix="$name/" -o "$out/$name.tar.gz" "$tag"
git archive --format=zip --prefix="$name/" -o "$out/$name.zip" "$tag"
git show "$tag:install.sh" > "$out/install.sh"
git show "$tag:install.ps1" > "$out/install.ps1"

if command -v sha256sum >/dev/null 2>&1; then sum='sha256sum'; else sum='shasum -a 256'; fi
(cd "$out" && $sum "$name.tar.gz" "$name.zip" install.sh install.ps1 > SHA256SUMS)
echo "Release assets in $out:"
cat "$out/SHA256SUMS"
