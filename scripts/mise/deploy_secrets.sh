#!/usr/bin/env bash
set -o errexit -o pipefail

if ! command -v mr >/dev/null; then echo 'Error: Deploy refreshes .env.production from 1Password with Mr. Moto'"'"'s mr secrets, and mr is not on PATH.'; exit 1; fi
mr secrets
root="$(git rev-parse --show-toplevel)"
main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
if [ "$(realpath "$main")" != "$(realpath "$root")" ]; then cp "$main/.env.production" "$root/.env.production"; fi
