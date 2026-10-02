#!/usr/bin/env bash
set -o errexit -o pipefail

cd manager
OP_SERVICE_ACCOUNT_TOKEN="$(bundle exec ruby -r ./lib/require -e 'print Settings.service_account_token')"
export OP_SERVICE_ACCOUNT_TOKEN
exec bundle exec ruby secrets.rb
