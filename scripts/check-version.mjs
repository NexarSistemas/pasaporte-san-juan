import { readFile } from 'node:fs/promises';

const documentedVersion = (await readFile(new URL('../VERSION', import.meta.url), 'utf8')).trim();
const configSource = await readFile(new URL('../js/config.js', import.meta.url), 'utf8');
const match = configSource.match(/version:\s*['"]([^'"]+)['"]/);

if (!match) throw new Error('GAME_CONFIG.version no encontrado');
if (documentedVersion !== match[1]) {
  throw new Error(`VERSION (${documentedVersion}) != GAME_CONFIG.version (${match[1]})`);
}

console.log(`Version sincronizada: ${documentedVersion}`);
