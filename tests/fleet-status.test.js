import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, writeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import process from 'node:process';
import { test } from 'node:test';
import { evaluate, loadFleet, main, report } from '../scripts/fleet-status.ts';

const REF = 'v0.45.0';
const REPOS = ['redhat-developer/rhdh-cli', 'redhat-developer/rhdh-plugins'];
const ALL_REPOS = [...REPOS, 'rhdh-parasol/rhdh-cli'];

function statusResult(repos = REPOS) {
  return {
    repos: repos.map(name => ({
      owner: name.split('/')[0], repo: name.split('/')[1], installed: true,
      current_ref: REF, expected_ref: REF,
    })),
    summary: { total: repos.length, installed: repos.length, not_installed: 0, drifted: 0, errored: 0 },
  };
}

function addDrift(result, field) {
  result.repos[0].drifts = [{ field, expected: REF, actual: 'v0.43.0' }];
  result.summary.drifted = 1;
  return result;
}

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'rhdh-fleet-js-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const manifest = join(root, 'repos.yaml');
  const outputDir = join(root, 'report');
  writeFileSync(manifest, `version: 1\ngithub:\n  fullsend_ref: ${REF}\n  repos:\n`
    + ALL_REPOS.map(name => `    - name: ${name}\n`).join(''));
  const state = { root, manifest, outputDir, raw: JSON.stringify(statusResult(ALL_REPOS)), exitCode: 0, calls: [] };
  state.runner = (binary, args, options) => {
    state.calls.push({ binary, args, options });
    writeSync(options.stdio[1], state.raw);
    writeSync(options.stdio[2], 'CLI diagnostics\n');
    return { status: state.exitCode };
  };
  state.invoke = (extra = [], env = {}, runner = state.runner) => {
    const logs = [];
    const exitCode = main({
      argv: ['--manifest', manifest, '--output-dir', outputDir, ...extra],
      env, log: value => logs.push(value), runner,
    });
    return { exitCode, output: logs.join('\n') };
  };
  return state;
}

test('matching versions pass', () => {
  const { rows, errors, warnings } = evaluate(statusResult(), REPOS, REF, 0);
  assert.equal(rows.length, 2);
  assert.deepEqual(errors, []);
  assert.deepEqual(warnings, []);
});

test('SHA equivalent to the manifest tag passes', () => {
  const result = statusResult();
  result.repos[0].current_ref = 'a'.repeat(40);
  assert.deepEqual(evaluate(result, REPOS, REF, 0).errors, []);
});

test('version drift fails even with zero CLI exit', () => {
  const result = addDrift(statusResult(), 'fullsend_ref');
  for (const exitCode of [0, 1]) {
    const status = evaluate(result, REPOS, REF, exitCode);
    assert.ok(status.errors.length);
    assert.equal(status.rows[0].status, 'FAIL');
  }
});

test('configuration drift warns despite a nonzero CLI exit', () => {
  const result = addDrift(statusResult(), '.github/workflows/fullsend.yaml');
  const status = evaluate(result, REPOS, REF, 1);
  assert.deepEqual(status.errors, []);
  assert.equal(status.rows[0].status, 'WARNING');
  assert.match(status.warnings[0], /fullsend.yaml/);
});

test('combined version and configuration drift fails and warns', () => {
  const result = addDrift(statusResult(), 'fullsend_ref');
  result.repos[0].drifts.push({ field: 'FULLSEND_MINT_URL', expected: 'new', actual: 'old' });
  const status = evaluate(result, REPOS, REF, 1);
  assert.ok(status.errors.length);
  assert.equal(status.warnings.length, 1);
});

test('missing installations and version pins fail', () => {
  const result = statusResult();
  delete result.repos[0].current_ref;
  assert.ok(evaluate(result, REPOS, REF, 0).errors.length);
  result.repos[0].installed = false;
  Object.assign(result.summary, { installed: 1, not_installed: 1 });
  assert.ok(evaluate(result, REPOS, REF, 1).errors.some(error => error.includes('not installed')));
});

test('API errors fail and may overlap installed status', () => {
  const result = statusResult();
  result.repos[0].error = '403: Resource not accessible by integration';
  result.summary.errored = 1;
  assert.match(evaluate(result, REPOS, REF, 1).errors[0], /403/);
});

test('wrong expected version fails', () => {
  const result = statusResult();
  result.repos[0].expected_ref = 'v0.43.0';
  assert.ok(evaluate(result, REPOS, REF, 0).errors.length);
});

test('incomplete, duplicate, and unexpected results fail', () => {
  const first = statusResult().repos[0];
  for (const repos of [[first], [first, first], [{ ...first, owner: 'rhdh-parasol' }]]) {
    const result = { ...statusResult(), repos };
    assert.throws(() => evaluate(result, REPOS, REF, 1));
  }
});

test('malformed status fields and summaries fail', () => {
  const cases = [null, {}, { repos: null }, { repos: [null] }];
  for (const [key, value] of [
    ['installed', 'true'], ['drifts', null], ['error', null], ['current_ref', null],
    ['expected_ref', null], ['forge', 'gitlab'],
  ]) {
    const result = statusResult();
    result.repos[0][key] = value;
    cases.push(result);
  }
  const invalidSummary = statusResult();
  invalidSummary.summary.total = 0;
  cases.push(invalidSummary);
  const invalidDrift = statusResult();
  invalidDrift.repos[0].drifts = [{ field: 'fullsend_ref' }];
  cases.push(invalidDrift);
  for (const result of cases) assert.throws(() => evaluate(result, REPOS, REF, 1));
});

test('unexplained CLI failures are fatal', () => {
  assert.ok(evaluate(statusResult(), REPOS, REF, 1).errors.length);
  for (const exitCode of [2, 127, 137]) {
    assert.ok(evaluate(addDrift(statusResult(), 'config'), REPOS, REF, exitCode).errors.length);
  }
});

test('CLI warnings are preserved and malformed warnings rejected', () => {
  const result = statusResult();
  result.warnings = ['configuration warning'];
  assert.deepEqual(evaluate(result, REPOS, REF, 0).warnings, result.warnings);
  for (const warnings of [null, [1], 'warning']) {
    assert.throws(() => evaluate({ ...result, warnings }, REPOS, REF, 0));
  }
});

test('Markdown escapes table values', () => {
  const rows = [{ repo: REPOS[0], status: 'FAIL', expected: REF, current: REF, details: ['bad | <script>\nnext'] }];
  const content = report(rows, ['failure'], []);
  assert.match(content, /bad &#124; &lt;script&gt; next/);
  assert.ok(!content.includes('<script>'));
});

test('default command runs fullsend and preserves diagnostics', t => {
  const state = fixture(t);
  const { exitCode, output } = state.invoke();
  assert.equal(exitCode, 0);
  assert.equal(state.calls[0].binary, 'fullsend');
  assert.deepEqual(state.calls[0].args, ['repos', 'status', '-f', state.manifest, '--json']);
  assert.equal(readFileSync(join(state.outputDir, 'status.json'), 'utf8'), state.raw);
  assert.equal(readFileSync(join(state.outputDir, 'stderr.log'), 'utf8'), 'CLI diagnostics\n');
  assert.equal(readFileSync(join(state.outputDir, 'exit-code.txt'), 'utf8'), '0\n');
  assert.match(output, /Checked 3 repositories/);
});

test('missing CLI, timeout, and termination generate failed reports', t => {
  const state = fixture(t);
  const cases = [
    [{ error: Object.assign(new Error('fullsend not found'), { code: 'ENOENT' }), status: null }, '127\n'],
    [{ error: Object.assign(new Error('fullsend timed out'), { code: 'ETIMEDOUT' }), status: null }, '124\n'],
    [{ signal: 'SIGTERM', status: null }, '143\n'],
  ];
  for (const [result, expectedCode] of cases) {
    assert.equal(state.invoke([], {}, () => result).exitCode, 1);
    assert.match(readFileSync(join(state.outputDir, 'summary.md'), 'utf8'), /FAIL/);
    assert.equal(readFileSync(join(state.outputDir, 'exit-code.txt'), 'utf8'), expectedCode);
  }
});

test('custom fullsend binary is passed without shell expansion', t => {
  const state = fixture(t);
  assert.equal(state.invoke(['--fullsend', '/custom path/fullsend']).exitCode, 0);
  assert.equal(state.calls[0].binary, '/custom path/fullsend');
});

test('prepare emits a matrix for all organizations without running fullsend', t => {
  const state = fixture(t);
  assert.deepEqual(loadFleet(state.manifest), { ref: REF, repos: ALL_REPOS });
  const output = join(state.root, 'github-output');
  assert.equal(state.invoke(['prepare', '--github-output', output]).exitCode, 0);
  const values = Object.fromEntries(readFileSync(output, 'utf8').trim().split('\n')
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
  assert.equal(values.version, REF);
  assert.deepEqual(JSON.parse(values.matrix), { include: [
    { owner: 'redhat-developer', repositories: 'rhdh-cli,rhdh-plugins' },
    { owner: 'rhdh-parasol', repositories: 'rhdh-cli' },
  ] });
  assert.equal(state.calls.length, 0);
});

test('organization filters affect the CLI and report coverage', t => {
  const state = fixture(t);
  for (const [owner, repos] of [['redhat-developer', REPOS], ['rhdh-parasol', ALL_REPOS.slice(-1)]]) {
    state.raw = JSON.stringify(statusResult(repos));
    assert.equal(state.invoke(['--owner', owner]).exitCode, 0);
    assert.deepEqual(state.calls.at(-1).args.slice(-2), ['--repo', `${owner}/*`]);
    const content = readFileSync(join(state.outputDir, 'summary.md'), 'utf8');
    for (const identity of repos) assert.ok(content.includes(identity));
    for (const identity of ALL_REPOS.filter(name => !repos.includes(name))) assert.ok(!content.includes(identity));
  }
  assert.throws(() => loadFleet(state.manifest, 'unknown-org'));
});

test('prepare scopes repository outputs to one organization', t => {
  const state = fixture(t);
  for (const [owner, names] of [['redhat-developer', 'rhdh-cli,rhdh-plugins'], ['rhdh-parasol', 'rhdh-cli']]) {
    const output = join(state.root, `${owner}-output`);
    assert.equal(state.invoke(['prepare', '--owner', owner, '--github-output', output]).exitCode, 0);
    const content = readFileSync(output, 'utf8');
    assert.ok(content.includes(`repositories=${names}\n`));
    assert.ok(content.includes(`version=${REF}\n`));
  }
  assert.equal(state.calls.length, 0);
});

test('other organizations are included without hardcoded names', t => {
  const state = fixture(t);
  writeFileSync(state.manifest, readFileSync(state.manifest, 'utf8').replaceAll('rhdh-parasol', 'another-org'));
  assert.equal(loadFleet(state.manifest).repos.at(-1), 'another-org/rhdh-cli');
});

test('invalid manifests are rejected', t => {
  const state = fixture(t);
  const original = readFileSync(state.manifest, 'utf8');
  const cases = [
    original.replace(REF, 'main'), original.replaceAll('redhat-developer', 'invalid org'),
    original.replaceAll('rhdh-cli', '*'), original.replaceAll('rhdh-plugins', 'rhdh-cli'),
    'github:\n  fullsend_ref: v0.45.0\n  repos: []\n', 'not: [valid',
  ];
  for (const content of cases) {
    writeFileSync(state.manifest, content);
    assert.throws(() => loadFleet(state.manifest));
  }
});

test('GitHub summary is written on success and malformed JSON', t => {
  const state = fixture(t);
  const summary = join(state.root, 'step-summary');
  for (const [raw, expectedExit] of [[state.raw, 0], ['broken JSON', 1]]) {
    state.raw = raw;
    writeFileSync(summary, '');
    assert.equal(state.invoke([], { GITHUB_STEP_SUMMARY: summary }).exitCode, expectedExit);
    assert.equal(readFileSync(summary, 'utf8'), readFileSync(join(state.outputDir, 'summary.md'), 'utf8'));
  }
});

test('warning annotations escape newlines and percent signs', t => {
  const state = fixture(t);
  const result = addDrift(statusResult(ALL_REPOS), 'config');
  result.repos[0].drifts[0].actual = 'old\n::error::injected%';
  state.raw = JSON.stringify(result);
  state.exitCode = 1;
  const { exitCode, output } = state.invoke([], { GITHUB_ACTIONS: 'true' });
  assert.equal(exitCode, 0);
  const annotations = output.split('\n').filter(line => line.startsWith('::'));
  assert.equal(annotations.length, 1);
  assert.match(annotations[0], /%0A::error::injected%25/);
});

test('help and invalid arguments do not run fullsend', t => {
  const state = fixture(t);
  assert.equal(state.invoke(['--help']).exitCode, 0);
  assert.equal(state.invoke(['--unknown']).exitCode, 2);
  assert.equal(state.invoke(['bad-command']).exitCode, 2);
  assert.equal(state.calls.length, 0);
});

test('real subprocess entrypoint accepts warning-only CLI failures', t => {
  const state = fixture(t);
  const binary = join(state.root, 'fake-fullsend');
  const data = join(state.root, 'fixture.json');
  writeFileSync(data, JSON.stringify(addDrift(statusResult(ALL_REPOS), 'config')));
  writeFileSync(binary, '#!/usr/bin/env node\n'
    + `process.stdout.write(require('node:fs').readFileSync(${JSON.stringify(data)}, 'utf8'));\n`
    + "process.stderr.write('test diagnostics\\n');\nprocess.exitCode = 1;\n", { mode: 0o755 });
  const result = spawnSync(process.execPath, [
    'scripts/fleet-status.ts',
    '--manifest', state.manifest, '--fullsend', binary, '--output-dir', state.outputDir,
  ], { encoding: 'utf8', env: {
    ...process.env, PATH: `${dirname(process.execPath)}:${process.env.PATH}`,
    GITHUB_ACTIONS: '', GITHUB_STEP_SUMMARY: '',
  } });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Checked 3 repositories: 0 errors, 1 warnings/);
  assert.equal(readFileSync(join(state.outputDir, 'exit-code.txt'), 'utf8'), '1\n');
});
