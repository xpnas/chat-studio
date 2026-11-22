import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { manifest, baseline, verifyRevision } from './studio-baselines.mjs';
import { summarize } from './contract-report.mjs';

test('matrix includes two release baselines and a separate pinned preview', () => {
  assert.deepEqual(manifest.baselines.map(row => row.id), ['legacy', 'stable', 'preview-agents']);
  for (const row of manifest.baselines) assert.match(baseline(row.id).sha, /^[a-f0-9]{40}$/);
  assert.equal(baseline('preview-agents').releaseGate, false);
  assert.throws(() => baseline('latest'), /Unknown/);
});
test('wrong checkout fails before any service is started', () => {
  const directory = mkdtempSync(join(tmpdir(), 'studio-revision-'));
  try {
    execFileSync('git', ['init', '-q', directory]);
    writeFileSync(join(directory, 'fixture'), 'wrong revision');
    execFileSync('git', ['-C', directory, 'add', 'fixture']);
    execFileSync('git', ['-C', directory, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
    assert.throws(() => verifyRevision('stable', directory), /Wrong Studio revision/);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});
const report = events => events.map(event => JSON.stringify(event)).join('\n');
test('contract reports executed and skipped counts separately', () => {
  assert.deepEqual(summarize('Resolving dependencies...\n' + report([
    {type: 'testDone', testID: 1, result: 'success', skipped: false, hidden: false},
    {type: 'testDone', testID: 2, result: 'success', skipped: true, hidden: false},
    {type: 'done', success: true},
  ])), {executed: 1, skipped: 1, failed: 0, errors: 0});
});
test('zero, skipped-only, hidden-only, failure, error and incomplete reports cannot pass', () => {
  for (const events of [
    [{type: 'done', success: true}],
    [{type: 'testDone', testID: 1, skipped: true}, {type: 'done', success: true}],
    [{type: 'testDone', testID: 1, hidden: true}, {type: 'done', success: true}],
    [{type: 'testDone', testID: 1, result: 'error'}, {type: 'done', success: false}],
    [{type: 'error'}, {type: 'done', success: true}],
    [{type: 'testDone', testID: 1, result: 'success'}],
  ]) assert.throws(() => summarize(report(events)), /did not pass/);
});
