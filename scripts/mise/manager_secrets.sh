#!/usr/bin/env bash
set -o errexit -o pipefail

service_file=".env.service"
if [ ! -f "$service_file" ]; then service_file="$HOME/.config/projects/.env.service"; fi
if [ ! -f "$service_file" ]; then echo 'Error: Missing .env.service in the repository or ~/.config/projects/.env.service.'; exit 1; fi
set -a
source "$service_file"
set +a
export OP_SERVICE_ACCOUNT_TOKEN="$SERVICE_ACCOUNT_TOKEN"
trap 'rm -f "${file:-}"' EXIT
while IFS= read -r environment; do
  if [[ ! "$environment" =~ ^[a-z0-9_-]+$ ]]; then echo "Error: Invalid secrets key: $environment"; exit 1; fi
  reference="$(node -e 'process.stdout.write(String((require("./config.json").secrets ?? {})[process.argv[1]] ?? ""))' "$environment")"
  if [ -z "$reference" ]; then echo "Skipping .env.$environment: secrets.$environment is not set in config.json."; continue; fi
  file="$(mktemp ".env.$environment.XXXXXX")"
  chmod 600 "$file"
  op read "$reference" > "$file"
  mv "$file" ".env.$environment"
  echo "Wrote .env.$environment"
done < <(node -e 'Object.keys(require("./config.json").secrets ?? {}).forEach((name) => process.stdout.write(name + "\n"))')
