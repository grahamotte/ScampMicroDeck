#!/usr/bin/env bash
set -o errexit -o pipefail

printf "%s\0" gems/*/ | xargs -0 -n 1 -P 4 sh -c '
  cd "$1"
  bundle exec ruby -Itest -e "Dir.glob(\"test/**/*_test.rb\").each { |f| require_relative f }"
' sh
