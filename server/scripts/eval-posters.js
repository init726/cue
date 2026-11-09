// 포스터 폴더를 /v1/analyze로 돌려 행사 판별·행사명·날짜·시간·장소의 정확도를 잰다.
// 사용법: node scripts/eval-posters.js <포스터 폴더> [--api https://cue-api-vczh.onrender.com]
// 폴더에 answers.json이 없으면 채워 넣을 틀(answers.template.json)만 만들고 끝난다.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const imageTypes = { '.jpg': 'jpeg', '.jpeg': 'jpeg', '.png': 'png', '.webp': 'webp', '.heic': 'heic' };
const offsetMinutes = 540;
// 서버는 사용자당 한 시간에 30번까지 분석하므로 그 전에 새 익명 사용자로 바꾼다.
const analysesPerUser = 25;

const normalize = (text) => String(text || '').toLowerCase().replace(/[\s\p{P}\p{S}]/gu, '');
const looselyEqual = (actual, expected) => {
  const a = normalize(actual);
  const b = normalize(expected);
  return Boolean(a && b) && (a.includes(b) || b.includes(a));
};
const localParts = (iso) => {
  const date = new Date(Date.parse(iso) + offsetMinutes * 60000).toISOString();
  return { date: date.slice(0, 10), time: date.slice(11, 16) };
};

// answer: { event: false } 또는 { title, date: 'YYYY-MM-DD', time: 'HH:MM', venue }. 빈 항목은 채점하지 않는다.
export function score(result, answer) {
  const expectEvent = answer.event !== false;
  const gotEvent = result.status === 'event' || result.status === 'past_event';
  const marks = { event: gotEvent === expectEvent };
  if (!expectEvent) return marks;
  const event = result.event || {};
  const sessions = (event.sessions || []).map((session) => ({ ...localParts(session.startsAt), venue: session.venue }));
  const period = event.period;
  if (answer.title) marks.title = looselyEqual(result.title || event.title, answer.title);
  if (answer.date) {
    marks.date = result.status === 'past_event'
      ? localParts(result.endedAt).date === answer.date
      : sessions.some((session) => session.date === answer.date) ||
        Boolean(period && period.startDate <= answer.date && answer.date <= period.endDate);
  }
  if (answer.time) marks.time = sessions.some((session) => session.time === answer.time);
  if (answer.venue) marks.venue = sessions.some((session) => looselyEqual(session.venue, answer.venue)) ||
    looselyEqual(period?.venue, answer.venue);
  return marks;
}

export function summarize(rows) {
  const fields = ['event', 'title', 'date', 'time', 'venue'];
  return Object.fromEntries(fields.map((field) => {
    const graded = rows.filter((row) => field in row.marks);
    const correct = graded.filter((row) => row.marks[field]).length;
    return [field, { correct, total: graded.length, rate: graded.length ? Math.round((correct / graded.length) * 100) : null }];
  }));
}

// 앱과 같은 조건(가로 최대 1800px, JPEG 품질 78)으로 줄여 보낸다. macOS의 sips가 없으면 원본을 보낸다.
async function imageDataUrl(file) {
  const type = imageTypes[path.extname(file).toLowerCase()];
  try {
    const out = path.join(await fs.mkdtemp(path.join(os.tmpdir(), 'cue-eval-')), 'poster.jpg');
    const width = Number(/pixelWidth: (\d+)/.exec(execFileSync('sips', ['-g', 'pixelWidth', file]).toString())?.[1]);
    execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '78',
      ...(width > 1800 ? ['--resampleWidth', '1800'] : []), file, '--out', out], { stdio: 'ignore' });
    return `data:image/jpeg;base64,${(await fs.readFile(out)).toString('base64')}`;
  } catch {
    if (type === 'heic') throw new Error(`${path.basename(file)}: HEIC는 macOS에서만 변환할 수 있어요.`);
    return `data:image/${type};base64,${(await fs.readFile(file)).toString('base64')}`;
  }
}

async function newToken(api) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (supabaseUrl && key) {
    const response = await fetch(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/signup`, {
      method: 'POST', headers: { apikey: key, 'content-type': 'application/json' }, body: '{}',
    });
    const body = await response.json();
    if (!response.ok || !body.access_token) throw new Error('Supabase 익명 로그인에 실패했어요.');
    return body.access_token;
  }
  const response = await fetch(`${api}/v1/session`, { method: 'POST' });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || '세션을 만들지 못했어요.');
  return body.token;
}

async function main() {
  const args = process.argv.slice(2);
  const apiIndex = args.indexOf('--api');
  const api = (apiIndex >= 0 ? args.splice(apiIndex, 2)[1] : process.env.CUE_API_URL || 'http://localhost:8787').replace(/\/$/, '');
  const folder = args[0];
  if (!folder) throw new Error('사용법: node scripts/eval-posters.js <포스터 폴더> [--api URL]');
  const files = (await fs.readdir(folder)).filter((name) => imageTypes[path.extname(name).toLowerCase()]).sort();
  if (!files.length) throw new Error('폴더에 JPG, PNG, WebP, HEIC 포스터가 없어요.');

  const answersFile = path.join(folder, 'answers.json');
  const answers = await fs.readFile(answersFile, 'utf8').then(JSON.parse).catch(() => null);
  if (!answers) {
    const template = Object.fromEntries(files.map((name) => [name, { title: '', date: '', time: '', venue: '' }]));
    await fs.writeFile(path.join(folder, 'answers.template.json'), `${JSON.stringify(template, null, 2)}\n`);
    console.log('answers.template.json을 만들었어요. 정답을 채우고 answers.json으로 이름을 바꾼 뒤 다시 실행하세요.');
    console.log('행사가 아닌 이미지는 { "event": false }로 적으세요.');
    return;
  }

  const rows = [];
  let token = null;
  for (const [index, name] of files.filter((file) => answers[file]).entries()) {
    if (index % analysesPerUser === 0) token = await newToken(api);
    process.stdout.write(`${name} ... `);
    const response = await fetch(`${api}/v1/analyze`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ image: await imageDataUrl(path.join(folder, name)), timezoneOffsetMinutes: offsetMinutes, defaultDurationMinutes: 120 }),
      signal: AbortSignal.timeout(180000),
    });
    const result = await response.json().catch(() => ({ status: 'error' }));
    if (!response.ok) result.status = `error ${response.status}`;
    const marks = score(result, answers[name]);
    rows.push({ name, status: result.status, marks, result });
    console.log(Object.entries(marks).map(([field, ok]) => `${field} ${ok ? 'O' : 'X'}`).join(', '));
  }

  const summary = summarize(rows);
  const cell = (marks, field) => (field in marks ? (marks[field] ? 'O' : 'X') : '-');
  const report = [
    `# 포스터 추출 정확도`, '',
    `- 서버: ${api}`, `- 포스터: ${rows.length}장`, `- 측정: ${new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}`, '',
    '| 항목 | 맞음 | 전체 | 정확도 |', '| --- | ---: | ---: | ---: |',
    ...Object.entries({ event: '행사 판별', title: '행사명', date: '날짜', time: '시간', venue: '장소' })
      .map(([field, label]) => `| ${label} | ${summary[field].correct} | ${summary[field].total} | ${summary[field].rate ?? '-'}% |`),
    '', '| 파일 | 결과 | 판별 | 행사명 | 날짜 | 시간 | 장소 |', '| --- | --- | :-: | :-: | :-: | :-: | :-: |',
    ...rows.map((row) => `| ${row.name} | ${row.status} | ${['event', 'title', 'date', 'time', 'venue'].map((field) => cell(row.marks, field)).join(' | ')} |`),
    '',
  ].join('\n');
  await fs.writeFile(path.join(folder, 'eval-report.md'), report);
  await fs.writeFile(path.join(folder, 'eval-results.json'), `${JSON.stringify(rows, null, 2)}\n`);
  console.log(`\n${report}\n결과를 eval-report.md와 eval-results.json에 저장했어요.`);
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
