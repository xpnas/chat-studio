import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const manifest = JSON.parse(readFileSync(new URL('./studio-baselines.json', import.meta.url), 'utf8'));
export function baseline(id) {
  const entry = manifest.baselines.find(item => item.id === id);
  if (!entry) throw Error(`Unknown Studio baseline: ${id}`);
  if (!/^[a-f0-9]{40}$/.test(entry.sha)) throw Error(`Invalid pinned SHA: ${id}`);
  return entry;
}
export function verifyRevision(id, directory) {
  const entry = baseline(id);
  const actual = execFileSync('git', ['-C', directory, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  if (actual !== entry.sha) throw Error(`Wrong Studio revision for ${id}: expected ${entry.sha}, got ${actual}`);
  return entry;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, id, directory] = process.argv.slice(2);
  if (command === 'matrix') {
    console.log(JSON.stringify({include: manifest.baselines.map(({id, sha, releaseGate}) => ({baseline: id, sha, releaseGate}))}));
  } else if (command === 'verify') {
    console.log(JSON.stringify(verifyRevision(id, directory)));
  } else if (command === 'entrypoint') {
    console.log(baseline(id).entrypoint);
  } else if (command === 'get') {
    console.log(JSON.stringify(baseline(id)));
  } else {
    throw Error('Usage: studio-baselines.mjs matrix|get ID|entrypoint ID|verify ID DIRECTORY');
  }
}
