#!/usr/bin/env bash
set -o errexit -o pipefail

node -e '
  const fs = require("fs");
  const config = JSON.parse(fs.readFileSync("config.json"));
  const base = process.env.LOCAL_DOMAIN || config.domain.split(".")[0];
  for (const subdomain of config.subdomains.filter(({ backend }) => backend)) {
    const prefix = subdomain.subdomains.includes("") ? "" : `${subdomain.subdomains[0]}.`;
    console.log(`${prefix}${base}`, 3000);
  }
' | xargs -n 2 sh -c 'pnpm --dir frontend exec portless alias "$1" "$2"' sh
node -e '
  const fs = require("fs");
  const config = JSON.parse(fs.readFileSync("config.json"));
  const base = process.env.LOCAL_DOMAIN || config.domain.split(".")[0];
  for (const subdomain of config.subdomains.filter(({ directory }) => directory)) {
    const prefix = subdomain.subdomains.includes("") ? "" : `${subdomain.subdomains[0]}.`;
    console.log(subdomain.name, `${prefix}${base}`);
  }
' | xargs -n 2 -P 0 sh -c 'VITE_SUBDOMAIN="$1" pnpm --dir frontend exec portless "$2" pnpm exec vite' sh
