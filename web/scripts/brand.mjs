#!/usr/bin/env node
// Copies the brand images that the app and the sign-in page serve from logo/web/ into public/assets/brand/,
// which the build then copies into the bundle. The copies are build output and are not committed.
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, '..', '..', 'logo', 'web');
const target = resolve(here, '..', 'public', 'assets', 'brand');

export const BRAND_FILES = [
  'OcuTalon-Logo-light-640.png',
  'OcuTalon-Logo-light-1280.png',
  'OcuTalon-Logo-dark-640.png',
  'OcuTalon-Logo-dark-1280.png',
  'icon-192.png',
  'favicon-32.png',
];

mkdirSync(target, { recursive: true });
for (const name of BRAND_FILES) {
  const from = join(source, name);
  if (!existsSync(from)) {
    console.error(`brand: ${from} does not exist`);
    process.exit(1);
  }
  copyFileSync(from, join(target, name));
}
console.log(`brand: copied ${BRAND_FILES.length} files to ${target}`);
