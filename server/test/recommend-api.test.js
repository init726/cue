import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

test('chosen topics, calendar busy times and the admin refresh work through the API', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'cue-recommend-'));
  // 실제 키가 .env에 있어도 외부 API를 부르지 않는다.
  Object.assign(process.env, { CUE_TEST_MODE: '1', CUE_DEMO_MODE: '0', SUPABASE_URL: '', SUPABASE_PUBLISHABLE_KEY: '',
    OPENAI_API_KEY: '', SEOUL_OPEN_API_KEY: '', TOUR_API_KEY: '', KAKAO_REST_API_KEY: '', DISCOVERY_DAILY_TOPICS: 'none',
    CATALOG_ADMIN_TOKEN: 'admin-token', CUE_DB_FILE: path.join(directory, 'test.sqlite'), CUE_DATA_FILE: path.join(directory, 'missing.json') });
  const { server } = await import('../src/server.js');
  const { store } = await import('../src/store.js');
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const call = async (route, token, body, method = 'POST') => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, {
      method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, ...await response.json() };
  };
  try {
    const start = new Date(Date.now() + 3 * 86400000);
    start.setUTCHours(6, 0, 0, 0);
    const end = new Date(start.getTime() + 2 * 3600000);
    await call('/v1/catalog/import', 'admin-token', { events: [{ title: '독립영화 상영회', venue: '서울아트시네마', category: '영화·상영회',
      startsAt: start.toISOString(), endsAt: end.toISOString(), sourceUrl: 'https://example.com/film' }] });
    const user = await call('/v1/session', null, {});
    const saved = await call('/v1/profile', user.token, { favoriteTopics: ['영화', '없는 분야', '영화'] }, 'PATCH');
    assert.deepEqual(saved.profile.favoriteTopics, ['영화']);
    const plain = (await call('/v1/recommendations', user.token, undefined, 'GET')).events;
    assert.deepEqual(plain.map((event) => [event.title, event.section]), [['독립영화 상영회', 'interest']]);
    const busy = `${new Date(start.getTime() - 3600000).toISOString()}/${end.toISOString()}`;
    const blocked = (await call(`/v1/recommendations?busy=${encodeURIComponent(busy)}`, user.token, undefined, 'GET')).events;
    assert.ok(blocked.every((event) => event.section !== 'fits'), '캘린더가 바쁜 시간이면 빈 시간 묶음에 넣지 않는다');
    const free = (await call(`/v1/recommendations?busy=${encodeURIComponent('2000-01-01T00:00:00Z/2000-01-01T01:00:00Z')}`, user.token, undefined, 'GET')).events;
    assert.equal(free[0].section, 'fits');
    assert.equal((await call('/v1/interactions', user.token, { eventId: free[0].id, action: 'recommendation_opened', kind: 'map' })).status, 201);
    assert.equal((await call('/v1/catalog/refresh', 'wrong', {})).status, 403);
    assert.equal((await call('/v1/catalog/refresh', 'admin-token', {})).status, 202);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    store.close();
    await fs.rm(directory, { recursive: true, force: true });
  }
});
