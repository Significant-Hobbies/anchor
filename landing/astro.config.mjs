// @ts-check
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://anchor.significanthobbies.com',
  output: 'static',
  trailingSlash: 'never',
  build: {
    format: 'file',
    // Three small pages with one stylesheet — inlining removes the round trip.
    inlineStylesheets: 'always',
  },
});
