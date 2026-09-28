#!/usr/bin/env bash
set -o errexit -o pipefail

printf "%s\0" gems/*/ | xargs -0 -n 1 -P 4 sh -c '
  cd "$1"
  bundle install
' sh
