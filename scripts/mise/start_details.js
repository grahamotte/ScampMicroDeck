#!/usr/bin/env node

const fs = require("fs");
const config = JSON.parse(fs.readFileSync("config.json"));
const subdomains = config.subdomains;
const base = process.env.LOCAL_DOMAIN || config.domain.split(".")[0];
const rows = subdomains.map((subdomain) => {
  const prefix = subdomain.subdomains.includes("") ? "" : `${subdomain.subdomains[0]}.`;
  const label = subdomain.name.toUpperCase();
  return [label, `https://${prefix}${base}.localhost`];
});
rows.push(["API", "http://localhost:3000"]);
const labelWidth = Math.max(...rows.map(([label]) => label.length));
const lines = [`${config.domain} · Development`, ...rows.map(([label, url]) => `${label.padEnd(labelWidth)}  ${url}`)];
const width = Math.max(...lines.map((line) => line.length));
console.log(`\n╔${"═".repeat(width + 2)}╗`);
for (const line of lines) console.log(`║ ${line.padEnd(width)} ║`);
console.log(`╚${"═".repeat(width + 2)}╝\n`);
