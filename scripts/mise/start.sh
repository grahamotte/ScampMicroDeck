#!/usr/bin/env bash
set -o errexit -o pipefail

exec mise run $(node -e '
  const fs = require("fs");
  const config = JSON.parse(fs.readFileSync("config.json"));
  const has = (source) => config.subdomains.some((subdomain) => subdomain.source === source);
  const tasks = [];
  if (has("backend")) tasks.push("start:backend", "start:jobs");
  if (has("backend") || has("frontend")) tasks.push("start:subdomains");
  if (has("website")) tasks.push("start:website");
  console.log(tasks.join(" ::: "));
')
