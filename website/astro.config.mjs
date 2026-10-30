import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";
import { readFileSync } from "fs";
import path from "path";

const root = path.resolve(import.meta.dirname, "..");
const config = JSON.parse(readFileSync(path.join(root, "config.json")));

export default defineConfig({
  site: `https://${config.domain}`,
  vite: {
    plugins: [tailwindcss()],
    server: {
      fs: {
        allow: [root],
      },
    },
  },
});
