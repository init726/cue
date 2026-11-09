import test from 'node:test';
import assert from 'node:assert/strict';
import { score, summarize } from '../scripts/eval-posters.js';

const event = (sessions, period = null) => ({ status: 'event', event: { title: '2026 재즈 페스티벌', sessions, period } });

test('poster answers are graded by field in Korean time', () => {
  const result = event([{ startsAt: '2026-11-06T07:00:00.000Z', endsAt: '2026-11-06T08:30:00.000Z', venue: '울산문화예술회관 대공연장' }]);
  assert.deepEqual(score(result, { title: '재즈 페스티벌', date: '2026-11-06', time: '16:00', venue: '울산문화예술회관' }),
    { event: true, title: true, date: true, time: true, venue: true });
  assert.deepEqual(score(result, { title: '록 페스티벌', date: '2026-11-07', time: '', venue: '' }),
    { event: true, title: false, date: false });
});

test('non-events, periods and past events are graded too', () => {
  assert.deepEqual(score({ status: 'not_event' }, { event: false }), { event: true });
  assert.deepEqual(score({ status: 'not_event' }, { title: '전시' }), { event: false, title: false });
  const period = event([], { startDate: '2026-11-01', endDate: '2026-11-30', venue: '서울시립미술관' });
  assert.deepEqual(score(period, { date: '2026-11-15', venue: '서울시립미술관 서소문본관' }), { event: true, date: true, venue: true });
  const past = { status: 'past_event', title: '2023 울산공업축제', endedAt: '2023-06-01T12:50:00.000Z' };
  assert.deepEqual(score(past, { title: '울산공업축제', date: '2023-06-01' }), { event: true, title: true, date: true });
});

test('summary counts only graded fields', () => {
  const summary = summarize([
    { marks: { event: true, title: true, date: false } },
    { marks: { event: true, title: true } },
    { marks: { event: false } },
  ]);
  assert.deepEqual(summary.title, { correct: 2, total: 2, rate: 100 });
  assert.deepEqual(summary.date, { correct: 0, total: 1, rate: 0 });
  assert.deepEqual(summary.event, { correct: 2, total: 3, rate: 67 });
  assert.deepEqual(summary.time, { correct: 0, total: 0, rate: null });
});
