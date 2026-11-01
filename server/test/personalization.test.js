import test from 'node:test';
import assert from 'node:assert/strict';
import { interestSignals, memoryFromSignal, preferencePenalty, rankingSignals, rankingWeights, rankRecommendations } from '../src/personalization.js';

test('explicit feedback outweighs views and old signals fade', () => {
  const currentTime = Date.parse('2027-01-01T00:00:00Z');
  const signals = interestSignals([
    { action: 'viewed', title: '미술 전시', category: '전시', created_at: '2026-12-31T00:00:00Z' },
    { action: 'not_interested', title: '미술 전시', category: '전시', created_at: '2026-12-31T00:00:00Z' },
    { action: 'saved', title: '음악 콘서트', category: '음악', created_at: '2026-01-01T00:00:00Z' },
  ], currentTime);
  assert.ok(signals.get('domain:미술').score < 0);
  assert.ok(signals.get('domain:음악').score < 0.1);
  assert.equal(memoryFromSignal('domain:미술', signals.get('domain:미술')).memoryType, 'avoidance');
  assert.equal(memoryFromSignal('domain:음악', signals.get('domain:음악')), null);
});

test('topic tags contribute to interest separately from broad categories', () => {
  const scores = interestSignals([
    { action: 'saved', title: '교육 행사', category: '교육', tags: '["AI","Programming"]', created_at: '2027-01-01T00:00:00Z' },
  ], Date.parse('2027-01-01T00:00:00Z'));
  assert.equal(scores.get('domain:교육').score, 4);
  assert.equal(scores.get('tag:ai').score, 2.2);
  assert.equal(scores.get('tag:programming').score, 2.2);
});

test('canceling a calendar entry does not erase topic interest', () => {
  const timestamp = '2027-01-01T00:00:00Z';
  const scores = interestSignals([
    { action: 'saved', title: '미술 전시', category: '전시', created_at: timestamp },
    { action: 'unsaved', title: '미술 전시', category: '전시', created_at: timestamp },
  ], Date.parse(timestamp));
  assert.equal(scores.get('domain:미술').score, 3);
});

test('recommendations filter expired deadlines and saved schedule conflicts', () => {
  const event = (id, startsAt, endsAt, deadline = null) =>
    ({ id, title: id, category: '음악', startsAt, endsAt, applicationDeadline: deadline });
  const catalog = [
    event('good', '2027-02-01T10:00:00Z', '2027-02-01T12:00:00Z'),
    event('conflict', '2027-02-01T15:00:00Z', '2027-02-01T17:00:00Z'),
    event('closed', '2027-02-02T10:00:00Z', '2027-02-02T12:00:00Z', '2026-01-01T00:00:00Z'),
  ];
  const results = rankRecommendations({ catalog, saved: [event('own', '2027-02-01T16:00:00Z', '2027-02-01T18:00:00Z')],
    interests: new Map([['domain:음악', 4]]), excluded: new Set(), currentTime: Date.parse('2027-01-01T00:00:00Z') });
  assert.deepEqual(results.map((item) => item.id), ['good']);
  assert.match(results[0].reason, /음악/);
});


test('AI education policy interest excludes art but keeps cross-format AI education', () => {
  const timestamp = '2027-01-01T00:00:00Z';
  const interests = new Map([...interestSignals([{ action: 'saved', title: 'AI 교육 정책방향 탐색토론회',
    category: '강연', tags: ['인공지능', '교육정책'], created_at: timestamp }], Date.parse(timestamp))]
    .map(([key, value]) => [key, value.score]));
  const base = { startsAt: '2027-02-01T10:00:00Z', endsAt: '2027-02-01T12:00:00Z' };
  const catalog = [
    { ...base, id: 'art', title: '신진미술인 지원 프로그램 최혜련 개인전 오늘 다시 사심을', category: '강연', tags: ['현대미술'] },
    { ...base, id: 'ai', title: 'AI 윤리 세미나', title: '교육 행사', category: '교육', tags: ['인공지능'] },
    { ...base, id: 'edu', title: '교육 AI 포럼', category: '강연', tags: ['미래교육'] },
    { ...base, id: 'future', title: '미래교육 컨퍼런스', title: '교육 행사', category: '교육', tags: ['미래교육'] },
  ];
  const results = rankRecommendations({ catalog, saved: [], interests, excluded: new Set(), currentTime: Date.parse(timestamp) });
  assert.deepEqual(new Set(results.map((item) => item.id)), new Set(['ai', 'edu', 'future']));
  assert.ok(results.every((item) => item.reason.includes('주제')));
});

test('logistical dismissal does not lower domain interest', () => {
  const timestamp = '2027-01-01T00:00:00Z';
  const rows = [{ action: 'saved', title: 'AI 세미나', created_at: timestamp },
    { action: 'not_interested', title: 'AI 세미나', metadata: { reason: '장소가 멂' }, created_at: timestamp }];
  assert.equal(interestSignals(rows, Date.parse(timestamp)).get('domain:AI').score, 4);
  rows[1].metadata.reason = '관심 없는 분야';
  assert.equal(interestSignals(rows, Date.parse(timestamp)).get('domain:AI').score, 1);
});

test('related technology is recommended but unrelated art is excluded', () => {
  const currentTime = Date.parse('2027-01-01T00:00:00Z');
  const base = { startsAt: '2027-02-01T10:00:00Z', endsAt: '2027-02-01T12:00:00Z' };
  const results = rankRecommendations({
    catalog: [
      { ...base, id: 'science', title: '과학 연구 세미나', domains: ['과학'] },
      { ...base, id: 'art', title: '미술 개인전', domains: ['미술'] },
    ], saved: [], interests: new Map([['domain:AI', 4]]), excluded: new Set(), currentTime,
  });
  assert.deepEqual(results.map((event) => event.id), ['science']);
});

test('signals are normalized and combined with one weight table', () => {
  const currentTime = Date.parse('2027-01-01T00:00:00Z');
  const signals = rankingSignals(
    { startsAt: '2026-12-01T00:00:00Z', endsAt: '2027-01-04T12:00:00Z' },
    { interestRaw: 16, peerCount: 8, community: { school: false, region: false, age: true }, distance: 6, currentTime },
  );
  assert.ok(signals.interest > 0.8 && signals.interest < 1);
  assert.equal(signals.peer, 1);
  assert.equal(signals.proximity, 0.8);
  assert.equal(signals.affinity, 0.4);
  assert.equal(signals.urgency, 0.5, '기간형 행사가 3.5일 뒤 끝난다');
  assert.equal(Object.values(rankingWeights).reduce((sum, value) => sum + value, 0), 1);
});

test('one topic cannot fill the top of the list and shares from people nearby get their own section', () => {
  const currentTime = Date.parse('2027-01-01T00:00:00Z');
  const at = (day) => ({ startsAt: `2027-02-0${day}T10:00:00Z`, endsAt: `2027-02-0${day}T12:00:00Z` });
  const shared = (id, owner, day) => ({ ...at(day), id, title: `동네 공연 ${id}`, domains: ['공연'], originKind: 'shared',
    sharingUserId: owner, community: { school: 'A' } });
  const results = rankRecommendations({
    catalog: [
      { ...at(1), id: 'ai1', title: 'AI 세미나 1', domains: ['AI'] },
      { ...at(2), id: 'ai2', title: 'AI 세미나 2', domains: ['AI'] },
      { ...at(3), id: 'ai3', title: 'AI 세미나 3', domains: ['AI'] },
      { ...at(4), id: 'robot', title: '로봇 데모데이', domains: ['로봇'] },
      shared('s1', 'p1', 5), shared('s2', 'p2', 6), shared('s3', 'p3', 7),
    ],
    saved: [], interests: new Map([['domain:AI', 4]]), excluded: new Set(), currentTime,
    context: { school: 'A' }, userId: 'viewer',
  });
  assert.deepEqual(results.map((event) => event.id), ['ai1', 'ai2', 'robot', 'ai3', 's1', 's2', 's3']);
  assert.ok(results.every((event) => !Object.hasOwn(event, 'discovery')));
});

test('activity regions compare by distance, not by how the name is written', () => {
  const event = (id, latitude) => ({ id, title: `행사 ${id}`, startsAt: '2099-01-01T01:00:00Z', endsAt: '2099-01-01T02:00:00Z',
    originKind: 'shared', sharingUserId: 'other', community: { region: '서울' }, locationLatitude: latitude, locationLongitude: 126.98 });
  const results = rankRecommendations({
    catalog: [event('near', 37.57), event('far', 35.1)], saved: [], interests: new Map(), excluded: new Set(),
    userId: 'viewer', context: { region: '서울시', regionLatitude: 37.56, regionLongitude: 126.98 },
  });
  assert.deepEqual(results.map((row) => row.id), ['near']);
  assert.match(results[0].reason, /km/);
  const noCoordinates = rankRecommendations({
    catalog: [{ ...event('text', null), locationLongitude: null }], saved: [], interests: new Map(), excluded: new Set(),
    userId: 'viewer', context: { region: '서울' },
  });
  assert.match(noCoordinates[0].reason, /같은 활동 지역/);
});

test('each recommendation carries its tab section and browsing never shows private-audience shares', () => {
  const currentTime = Date.parse('2027-01-01T00:00:00Z');
  const at = (day) => ({ startsAt: `2027-02-0${day}T10:00:00Z`, endsAt: `2027-02-0${day}T12:00:00Z` });
  const results = rankRecommendations({
    catalog: [
      { ...at(1), id: 'ai', title: 'AI 세미나', domains: ['AI'] },
      { ...at(2), id: 'near', title: '동네 공연', domains: ['공연'], originKind: 'shared', sharingUserId: 'p', community: { school: 'A' } },
      { ...at(3), id: 'far-art', title: '미술 개인전', domains: ['미술'], locationLatitude: 35.1, locationLongitude: 129 },
      { ...at(4), id: 'close-music', title: '재즈 공연', domains: ['음악'], locationLatitude: 37.56, locationLongitude: 126.98 },
      { ...at(5), id: 'stranger', title: '다른 학교 공연', domains: ['공연'], originKind: 'shared', sharingUserId: 'q', community: { school: 'B' } },
    ],
    saved: [], interests: new Map([['domain:AI', 4]]), excluded: new Set(), currentTime, explore: true,
    context: { school: 'A', regionLatitude: 37.55, regionLongitude: 126.98 }, userId: 'viewer',
  });
  assert.deepEqual(results.map((event) => [event.id, event.section]),
    [['ai', 'interest'], ['near', 'nearby'], ['close-music', 'explore'], ['far-art', 'explore']]);
});

test('shares near the device come first and the same age band breaks ties, whatever the interests', () => {
  const at = { startsAt: '2099-02-01T10:00:00Z', endsAt: '2099-02-01T12:00:00Z' };
  const shared = (id, latitude, ageBand) => ({ ...at, id, title: `공유 ${id}`, domains: ['미술'], originKind: 'shared',
    sharingUserId: id, community: { ageBand }, locationLatitude: latitude, locationLongitude: 126.98 });
  const results = rankRecommendations({
    catalog: [shared('far', 37.75, '20s'), shared('near-other-age', 37.565, '40plus'), shared('near-same-age', 37.567, '20s'),
      shared('too-far', 35.1, '20s')],
    saved: [], interests: new Map([['domain:AI', 4]]), excluded: new Set(), currentTime: Date.parse('2099-01-01T00:00:00Z'),
    userId: 'viewer', context: { ageBand: '20s', regionLatitude: 37.56, regionLongitude: 126.98 },
  });
  assert.deepEqual(results.map((event) => [event.id, event.section]),
    [['near-same-age', 'nearby'], ['near-other-age', 'nearby'], ['far', 'nearby'], ['too-far', 'nearby']]);
  assert.match(results[0].reason, /내 주변 약 1km · 같은 연령대/);
});

test('chosen topics count as interests from the first day', () => {
  const at = { startsAt: '2099-02-01T10:00:00Z', endsAt: '2099-02-01T12:00:00Z' };
  const args = { catalog: [{ ...at, id: 'film', title: '독립영화 상영회', domains: ['영화'] }], saved: [], excluded: new Set(),
    currentTime: Date.parse('2099-01-01T00:00:00Z') };
  assert.equal(rankRecommendations({ ...args, interests: new Map() }).length, 0);
  const results = rankRecommendations({ ...args, interests: new Map([['domain:영화', -2]]), favorites: ['영화'] });
  assert.deepEqual(results.map((event) => [event.id, event.section]), [['film', 'interest']]);
});

test('dismissal reasons become distance, price and time-of-day penalties', () => {
  const now = Date.parse('2027-01-01T00:00:00Z');
  const signals = interestSignals([
    { action: 'not_interested', metadata: { reason: '장소가 멂' }, title: 'a', created_at: '2027-01-01T00:00:00Z' },
    { action: 'not_interested', metadata: { reason: '비쌈' }, title: 'b', created_at: '2027-01-01T00:00:00Z' },
    { action: 'not_interested', metadata: { reason: '시간 안 맞음' }, title: 'c', start_at: '2027-01-04T11:00:00Z', created_at: '2027-01-01T00:00:00Z' },
    { action: 'not_interested', metadata: { reason: '시간 안 맞음' }, title: 'd', start_at: '2027-01-05T12:00:00Z', created_at: '2027-01-01T00:00:00Z' },
  ], now);
  assert.equal(signals.get('pref:far').count, 1);
  assert.equal(signals.get('pref:band:weekday_evening').count, 2, '월·화 저녁(한국 시각 20·21시)');
  assert.equal(memoryFromSignal('pref:band:weekday_evening', { score: 3, count: 2 }), null);
  const interests = new Map([...signals].map(([key, value]) => [key, value.score]));
  assert.equal(preferencePenalty({ startsAt: '2027-01-11T11:00:00Z', participationFee: '전석 30,000원' }, interests, 15), 0.6 * 0.7 * 0.7);
  assert.equal(preferencePenalty({ startsAt: '2027-01-09T05:00:00Z', participationFee: '무료' }, interests, 3), 1);
  assert.equal(preferencePenalty({ startsAt: '2027-01-09T05:00:00Z', participationFee: '입장료 0원' }, interests, 3), 1);
});

test('this week fits free calendar time and events next to a saved plan get their own sections', () => {
  const now = Date.parse('2027-01-04T00:00:00Z'); // 월요일 오전 9시(한국)
  const at = (day, hour) => new Date(Date.UTC(2027, 0, day, hour - 9)).toISOString();
  const event = (id, day, hour, extra = {}) => ({ id, title: id, domains: ['음악'], startsAt: at(day, hour), endsAt: at(day, hour + 2),
    locationLatitude: 37.56, locationLongitude: 126.97, ...extra });
  const saved = [{ title: '덕수궁 산책', startsAt: at(7, 13), endsAt: at(7, 14), locationLatitude: 37.5658, locationLongitude: 126.9751 }];
  const results = rankRecommendations({
    catalog: [event('busy-wed', 6, 19), event('free-sat', 9, 15), event('free-thu', 7, 19, { locationLatitude: 37.6, locationLongitude: 127.2 }),
      event('near-plan', 7, 16), event('next-month', 30, 15)],
    saved, interests: new Map([['domain:음악', 4]]), excluded: new Set(), currentTime: now, explore: true,
    busy: [{ start: Date.parse(at(6, 18)), end: Date.parse(at(6, 21)) }],
  });
  const by = (section) => results.filter((item) => item.section === section).map((item) => item.id);
  assert.deepEqual(by('sameDay'), ['near-plan'], '저장한 일정 근처가 먼저 자리를 잡는다');
  assert.deepEqual(by('fits'), ['free-sat', 'free-thu'], '주말 먼저');
  assert.match(results.find((item) => item.id === 'free-sat').reason, /토요일 15:00에 캘린더가 비어 있어요/);
  assert.ok(!by('fits').includes('busy-wed'), '바쁜 시간과 겹치면 빠진다');
  const noBusy = rankRecommendations({ catalog: [event('near-plan', 7, 16), event('other', 30, 15)], saved,
    interests: new Map([['domain:음악', 4]]), excluded: new Set(), currentTime: now });
  assert.deepEqual(noBusy.filter((item) => item.section === 'sameDay').map((item) => item.id), ['near-plan']);
  assert.match(noBusy[0].reason, /덕수궁 산책 일정 근처 약 \d+m/);
  assert.equal(noBusy.filter((item) => item.section === 'fits').length, 0, '캘린더를 모르면 빈 시간 묶음이 없다');
});
