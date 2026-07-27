import { defineConfig } from "astro/config";

/**
 * Mode static : landing produit Astro pure (HTML + SCSS).
 * Admin DataStudio = HTMX Django sur PUBLIC_DJANGO_URL/admin/.
 * Pour SSR Docker plus tard : basculer output:'server' + @astrojs/node.
 */
export default defineConfig({
  output: "static",
  server: {
    host: "0.0.0.0",
    port: 4321,
  },
  vite: {
    css: {
      preprocessorOptions: {
        scss: {
          loadPaths: ["./src/styles"],
        },
      },
    },
  },
});
