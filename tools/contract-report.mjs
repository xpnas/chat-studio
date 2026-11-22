import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function summarize(report) {
  const results = new Map();
  let done;
  let errors = 0;
  let started = false;
  for (const line of report.replace(/^\uFEFF/, '').split(/\r?\n/)) {
    if (!line.trim()) continue;
    // Flutter may print tool setup before the JSON reporter starts. Once the
    // event stream begins, malformed or truncated records must still fail.
    if (!started && !line.trimStart().startsWith('{')) continue;
    started = true;
    const event = JSON.parse(line);
    if (event.type === 'testDone' && !event.hidden) results.set(event.testID, event);
    if (event.type === 'error') errors++;
    if (event.type === 'done') done = event;
  }
  const rows = [...results.values()];
  const skipped = rows.filter(row => row.skipped).length;
  const executed = rows.length - skipped;
  const failed = rows.filter(row => !row.skipped && row.result !== 'success').length;
  const summary = {executed, skipped, failed, errors};
  if (!done?.success || executed === 0 || failed || errors) {
    throw Error(`Contract did not pass: ${JSON.stringify(summary)}`);
  }
  return summary;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(summarize(readFileSync(process.argv[2], 'utf8'))));
}
