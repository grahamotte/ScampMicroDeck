#!/usr/bin/env bash
set -o errexit -o pipefail

if [ -n "$(git status --porcelain)" ]; then echo 'Error: You have uncommitted changes. Please commit or stash them before merging.'; exit 1; fi
git fetch origin master
if git show-ref --verify --quiet "refs/heads/$usage_branch"; then git checkout "$usage_branch"; else git checkout -b "$usage_branch" --no-track origin/master; fi
echo "Merge recovery point: $(git rev-parse HEAD)"
legacy_url="$(git remote get-url upstream 2>/dev/null || true)"
case "$legacy_url" in
  git@github.com:grahamotte/codemoto.org.git|https://github.com/grahamotte/codemoto.org|https://github.com/grahamotte/codemoto.org.git|ssh://git@github.com/grahamotte/codemoto.org.git)
    if git remote get-url codemoto >/dev/null 2>&1; then git remote remove upstream; else git remote rename upstream codemoto; fi
    ;;
esac
if git remote get-url codemoto >/dev/null 2>&1; then git remote set-url codemoto git@github.com:grahamotte/codemoto.org.git; else git remote add codemoto git@github.com:grahamotte/codemoto.org.git; fi
git config remote.codemoto.tagOpt --no-tags
git config remote.origin.gh-resolved base
git fetch --no-tags codemoto master
git ls-remote --tags codemoto | { grep -v "\^{}$" || true; } | while read -r sha ref; do tag="${ref#refs/tags/}"; if [ "$(git rev-parse -q --verify "refs/tags/$tag")" = "$sha" ]; then git tag -d "$tag"; fi; done
if ! git merge-base HEAD codemoto/master >/dev/null; then echo 'Error: This repository does not share history with Code Moto.'; exit 1; fi
git merge --no-edit --no-ff codemoto/master
