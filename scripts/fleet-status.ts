#!/usr/bin/env node
/** Run fullsend fleet verification locally or in CI and write status reports. */
import {
  appendFileSync, closeSync, mkdirSync, openSync, readFileSync, writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { constants } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { parseArgs } from 'node:util';
import { parse } from 'yaml';

type JsonObject = Record<string, unknown>;
type Row = {
  repo: string;
  status: 'PASS' | 'WARNING' | 'FAIL';
  expected: string;
  current: string;
  details: string[];
};
type Evaluation = { rows: Row[]; errors: string[]; warnings: string[] };
type RunResult = {
  status: number | null;
  signal?: string | null;
  error?: Error & { code?: string };
};
type Runner = (binary: string, args: string[], options: {
  stdio: ['ignore', number, number]; timeout: number; killSignal: 'SIGKILL';
}) => RunResult;
type CliValues = {
  manifest: string;
  owner?: string;
  'github-output'?: string;
  fullsend: string;
  'output-dir': string;
  help?: boolean;
};
type MainOptions = {
  argv?: string[];
  env?: Record<string, string | undefined>;
  log?: (value: string) => void;
  runner?: Runner;
};

const isObject = (value: unknown): value is JsonObject =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const errorMessage = (error: unknown): string => error instanceof Error ? error.message : String(error);

export function loadFleet(path: string, owner?: string): { ref: string; repos: string[] } {
  const manifest: unknown = parse(readFileSync(path, 'utf8'));
  const github = isObject(manifest) ? manifest.github : undefined;
  if (!isObject(github) || typeof github.fullsend_ref !== 'string'
      || !/^v\d+\.\d+\.\d+$/.test(github.fullsend_ref)) {
    throw new Error('github.fullsend_ref must be a release tag such as v0.45.0');
  }
  if (!Array.isArray(github.repos) || github.repos.length === 0) {
    throw new Error('fleet must contain concrete owner/repository names');
  }
  const names: unknown[] = github.repos.map((entry: unknown) => isObject(entry) ? entry.name : undefined);
  if (!names.every((name): name is string => typeof name === 'string'
      && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(name))) {
    throw new Error('fleet must contain concrete owner/repository names');
  }
  let repos = [...names];
  if (new Set(repos).size !== repos.length) throw new Error('duplicate repositories in manifest');
  if (owner !== undefined) {
    repos = repos.filter(name => name.split('/')[0] === owner);
    if (repos.length === 0) throw new Error(`manifest contains no ${owner} repositories to check`);
  }
  return { ref: github.fullsend_ref, repos };
}

export function fleetMatrix(repos: string[]): { include: { owner: string; repositories: string }[] } {
  const organizations = new Map<string, string[]>();
  for (const identity of repos) {
    const [owner, repo] = identity.split('/');
    if (!organizations.has(owner)) organizations.set(owner, []);
    organizations.get(owner)!.push(repo);
  }
  return { include: [...organizations].map(([owner, names]) => ({
    owner, repositories: names.join(','),
  })) };
}

export function readStatus(
  fullsend: string, manifest: string, owner: string | undefined,
  outputDir: string, runner: Runner = spawnSync,
): { result: unknown; exitCode: number } {
  mkdirSync(outputDir, { recursive: true });
  const args = ['repos', 'status', '-f', manifest, '--json'];
  if (owner !== undefined) args.push('--repo', `${owner}/*`);
  const stdout = openSync(join(outputDir, 'status.json'), 'w');
  const stderr = openSync(join(outputDir, 'stderr.log'), 'w');
  let result: RunResult;
  try {
    result = runner(fullsend, args, {
      stdio: ['ignore', stdout, stderr], timeout: 600_000, killSignal: 'SIGKILL',
    });
  } catch (error) {
    result = { error: error instanceof Error ? error : new Error(String(error)), status: null };
  } finally {
    closeSync(stdout);
    closeSync(stderr);
  }
  const exitCode = result.error
    ? (result.error.code === 'ETIMEDOUT' ? 124 : 127)
    : (result.status ?? 128 + (constants.signals[result.signal as keyof typeof constants.signals] ?? 0));
  writeFileSync(join(outputDir, 'exit-code.txt'), `${exitCode}\n`);
  if (result.error || result.status === null) {
    const message = result.error?.message ?? `fullsend terminated by ${result.signal}`;
    appendFileSync(join(outputDir, 'stderr.log'), `${message}\n`);
    throw new Error(`could not run fullsend: ${message}`);
  }
  return { result: JSON.parse(readFileSync(join(outputDir, 'status.json'), 'utf8')), exitCode };
}

export function evaluate(result: unknown, expectedRepos: string[], expectedRef: string, exitCode: number): Evaluation {
  if (!isObject(result) || !Array.isArray(result.repos)) {
    throw new Error('status JSON must contain a repos array');
  }
  const rows: Row[] = [], errors: string[] = [], warnings: string[] = [];
  const seen = new Set(), expectedSet = new Set(expectedRepos);
  const counts = { total: 0, installed: 0, not_installed: 0, drifted: 0, errored: 0 };
  for (const repo of result.repos) {
    if (!isObject(repo)) throw new Error('invalid repository result');
    if (typeof repo.owner !== 'string' || typeof repo.repo !== 'string') {
      throw new Error('missing repository identity');
    }
    const identity = `${repo.owner}/${repo.repo}`;
    if (!expectedSet.has(identity) || seen.has(identity)) {
      throw new Error(`unexpected or duplicate repository result: ${identity}`);
    }
    seen.add(identity);
    const {
      installed, drifts = [], error = '', current_ref: current = '',
      expected_ref: expected = '', forge = 'github',
    } = repo;
    if (typeof installed !== 'boolean' || !Array.isArray(drifts)
        || typeof error !== 'string' || typeof current !== 'string' || typeof expected !== 'string'
        || forge !== 'github') {
      throw new Error(`invalid repository status: ${identity}`);
    }
    counts.total++;
    counts.installed += Number(installed);
    counts.not_installed += Number(!installed);
    counts.drifted += Number(drifts.length > 0);
    counts.errored += Number(error !== '');
    const repoErrors: string[] = [], repoWarnings: string[] = [];
    if (error) repoErrors.push(`API/check error: ${error}`);
    if (!installed) repoErrors.push('fullsend is not installed');
    if (!current) repoErrors.push('missing or unreadable version pin');
    if (expected !== expectedRef) repoErrors.push('expected version does not match manifest');
    for (const drift of drifts) {
      if (!isObject(drift)
          || ['field', 'expected', 'actual'].some(key => typeof drift[key] !== 'string')) {
        throw new Error(`invalid drift entry: ${identity}`);
      }
      // The CLI resolves tag/SHA equivalence. Comparing ref strings here
      // would falsely reject installations pinned to the release's SHA.
      const target = drift.field === 'fullsend_ref' ? repoErrors : repoWarnings;
      target.push(`${drift.field}: expected ${drift.expected}; actual ${drift.actual}`);
    }
    errors.push(...repoErrors.map(detail => `${identity}: ${detail}`));
    warnings.push(...repoWarnings.map(detail => `${identity}: ${detail}`));
    rows.push({
      repo: identity, status: repoErrors.length ? 'FAIL' : repoWarnings.length ? 'WARNING' : 'PASS',
      expected, current, details: [...repoErrors, ...repoWarnings],
    });
  }
  const missing = expectedRepos.filter(repo => !seen.has(repo)).sort();
  if (missing.length) throw new Error(`missing repository results: ${missing.join(', ')}`);
  const summary = result.summary;
  if (!isObject(summary)
      || Object.entries(counts).some(([key, value]) => summary[key] !== value)) {
    throw new Error('status summary does not match repository results');
  }
  const cliWarnings = result.warnings === undefined ? [] : result.warnings;
  if (!Array.isArray(cliWarnings) || cliWarnings.some(value => typeof value !== 'string')) {
    throw new Error('invalid CLI warnings');
  }
  warnings.push(...cliWarnings);
  if (exitCode !== 0 && !errors.length && !(exitCode === 1 && counts.drifted > 0)) {
    errors.push(`fullsend exited unexpectedly with code ${exitCode}`);
  }
  return { rows, errors, warnings };
}

const escapeAnnotation = (value: unknown): string => String(value)
  .replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
const markdown = (value: unknown): string => String(value).replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('|', '&#124;')
  .replaceAll('\r', ' ').replaceAll('\n', ' ');

export function report(rows: Row[], errors: string[], warnings: string[]): string {
  const lines = [
    '## Fullsend fleet verification', '',
    `Result: **${errors.length ? 'FAIL' : 'PASS'}** — ${errors.length} errors, ${warnings.length} warnings.`,
    '', '| Repository | Result | Expected ref | Current ref | Details |',
    '| --- | --- | --- | --- | --- |',
  ];
  for (const row of rows) {
    const cells = [row.repo, row.status, row.expected, row.current || 'missing', row.details.join('; ') || 'none'];
    lines.push(`| ${cells.map(markdown).join(' | ')} |`);
  }
  for (const [title, messages] of [['Errors', errors], ['Warnings', warnings]] as const) {
    if (messages.length) lines.push('', `### ${title}`, '', ...messages.map(message => `- ${markdown(message)}`));
  }
  return `${lines.join('\n')}\n`;
}

export function main({ argv = process.argv.slice(2), env = process.env, log = console.log, runner = spawnSync }: MainOptions = {}): number {
  let values: CliValues, command: string;
  try {
    const args = parseArgs({ args: argv, allowPositionals: true, options: {
      manifest: { type: 'string', default: 'repos.yaml' },
      owner: { type: 'string' },
      'github-output': { type: 'string' },
      fullsend: { type: 'string', default: 'fullsend' },
      'output-dir': { type: 'string', default: 'fleet-report' },
      help: { type: 'boolean', short: 'h' },
    } });
    values = args.values;
    command = args.positionals[0] ?? 'check';
    if (args.positionals.length > 1 || !['prepare', 'check'].includes(command)) {
      throw new Error('command must be prepare or check (default: check)');
    }
    if (values.help) {
      log('Usage: node scripts/fleet-status.ts [check|prepare] [--manifest PATH] [--owner ORG]\n'
        + '  [--fullsend PATH] [--output-dir DIR] [--github-output PATH]\n'
        + 'Check all manifest repositories by default and write fleet-report/summary.md.');
      return 0;
    }
  } catch (error) {
    log(`ERROR: ${errorMessage(error)}`);
    return 2;
  }
  let rows: Row[] = [], errors: string[] = [], warnings: string[] = [];
  try {
    const { ref, repos } = loadFleet(values.manifest, values.owner);
    if (command === 'prepare') {
      const output = values['github-output'] ?? env.GITHUB_OUTPUT;
      if (!output) throw new Error('prepare requires --github-output or GITHUB_OUTPUT');
      appendFileSync(output, `version=${ref}\nmatrix=${JSON.stringify(fleetMatrix(repos))}\n`);
      if (values.owner !== undefined) {
        appendFileSync(output, `repositories=${repos.map(repo => repo.split('/')[1]).join(',')}\n`);
      }
      return 0;
    }
    const { result, exitCode } = readStatus(values.fullsend, values.manifest, values.owner, values['output-dir'], runner);
    ({ rows, errors, warnings } = evaluate(result, repos, ref, exitCode));
  } catch (error) {
    errors.push(`Could not verify fleet: ${errorMessage(error)}`);
  }
  for (const [level, messages] of [['error', errors], ['warning', warnings]] as const) {
    for (const message of messages) {
      log(env.GITHUB_ACTIONS === 'true' ? `::${level}::${escapeAnnotation(message)}` : `${level.toUpperCase()}: ${message}`);
    }
  }
  if (command === 'check') {
    const content = report(rows, errors, warnings);
    const destination = join(values['output-dir'], 'summary.md');
    mkdirSync(values['output-dir'], { recursive: true });
    writeFileSync(destination, content);
    for (const row of rows) {
      log(`${row.repo}: ${row.status} (current ${row.current || 'missing'}, expected ${row.expected})`);
    }
    log(`Checked ${rows.length} repositories: ${errors.length} errors, ${warnings.length} warnings.`);
    log(`Report: ${destination}`);
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, content);
  }
  return Number(errors.length > 0);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`ERROR: ${errorMessage(error)}`);
    process.exitCode = 1;
  }
}
