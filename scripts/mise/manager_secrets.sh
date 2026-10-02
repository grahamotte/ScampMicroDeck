#!/usr/bin/env bash
set -o errexit -o pipefail

service_file=".env.service"
if [ ! -f "$service_file" ]; then service_file="$HOME/.config/projects/.env.service"; fi
if [ ! -f "$service_file" ]; then echo 'Error: Missing .env.service in the repository or ~/.config/projects/.env.service.'; exit 1; fi
set -a
source "$service_file"
set +a
export OP_SERVICE_ACCOUNT_TOKEN="$SERVICE_ACCOUNT_TOKEN"
cd manager
exec bundle exec ruby secrets.rb
