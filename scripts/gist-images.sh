#!/usr/bin/env bash
# Hosts image files on one GitHub gist (gists are git repos, so binaries push where `gh gist create` refuses them)
# and prints one raw URL per file, in order. From the chop-conventions gist-image skill.
# Usage: scripts/gist-images.sh "<gist description>" <file>...
set -euo pipefail
desc=$1; shift
[ $# -gt 0 ] || { echo "no files" >&2; exit 1; }
url=$(gh gist create --desc "$desc" - <<<"# $desc" 2>&1 | grep -o 'https://gist.github.com/[^ ]*')
id=$(basename "$url")
user=$(gh api user --jq .login)
work=$(mktemp -d "${TMPDIR:-/tmp}/gist-images.XXXXXX")
# gh's token signs the git traffic, so no stored credential for gist.github.com is needed.
cred='credential.helper=!gh auth git-credential'
git -c "$cred" clone -q "$url" "$work/gist"
cp "$@" "$work/gist/"
(cd "$work/gist" && git add . && git -c user.name=gist-images -c user.email=gist-images@localhost commit -qm "images" && git -c "$cred" push -q)
rm -r "$work"
for f in "$@"; do echo "https://gist.githubusercontent.com/$user/$id/raw/$(basename "$f")"; done
