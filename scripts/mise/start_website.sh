#!/usr/bin/env bash
set -o errexit -o pipefail

host=$(node -e '
  const fs = require("fs");
  const config = JSON.parse(fs.readFileSync("config.json"));
  const base = process.env.LOCAL_DOMAIN || config.domain.split(".")[0] || config.database;
  const subdomain = config.subdomains.find(({ source }) => source === "website");
  const prefix = subdomain.subdomains.includes("") ? "" : `${subdomain.subdomains[0]}.`;
  console.log(`${prefix}${base}`);
')
cd website && exec pnpm exec portless "$host" pnpm exec astro dev
