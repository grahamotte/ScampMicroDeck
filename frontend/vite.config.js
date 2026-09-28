import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { execSync } from "child_process";
import { readFileSync } from "fs";
import path from "path";
import { defineConfig } from "vite";

const config = JSON.parse(
  readFileSync(path.resolve(__dirname, "..", "config.json")),
);
const subdomain = config.subdomains.find(
  ({ name }) => name === (process.env.VITE_SUBDOMAIN || "www"),
);

export default defineConfig({
  cacheDir: path.resolve(__dirname, "node_modules/.vite", subdomain.name),
  root: path.resolve(__dirname, "..", subdomain.directory),
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": __dirname,
    },
  },
  server: {
    allowedHosts: [".trycloudflare.com"],
    host: "127.0.0.1",
    strictPort: true,
    proxy: {
      "/api": {
        target: "http://localhost:3000",
      },
    },
  },
  define: {
    "import.meta.env.VITE_TITLE": JSON.stringify(config.site.title),
    "import.meta.env.VITE_DESCRIPTION": JSON.stringify(config.site.description),
    "import.meta.env.VITE_THEME_COLOR": JSON.stringify(config.site.themeColor),
    VITE_RELEASE: JSON.stringify(
      execSync("git rev-parse HEAD").toString().trim()
    ),
  },
  build: {
    chunkSizeWarningLimit: 100000000,
    emptyOutDir: true,
    outDir: path.resolve(__dirname, "dist", subdomain.name),
  },
  optimizeDeps: {
    rollupOptions: {},
  },
});
