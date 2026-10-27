import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { communityContext, eventOrigin } from '../src/community.js';
import { rankRecommendations } from '../src/personalization.js';
import { CloudStore } from '../src/cloud-store.js';

test('community matching supplements interests and source labels stay truthful', () => {
  assert.equal(eventOrigin({ origin_kind: 'shared', source_url: 'https://example.com' }), 'shared');
  assert.equal(eventOrigin({ source_url: 'https://example.com' }), 'web');
  assert.equal(eventOrigin({ origin_kind: 'catalog', source_url: 'https://example.com' }), 'catalog');
  assert.equal(eventOrigin({ origin_kind: 'web', source_url: 'https://example.com' }), 'web');
  assert.equal(eventOrigin({ tags: ['시연용'] }), 'demo');
  assert.equal(eventOrigin({}), 'catalog');
  assert.deepEqual(communityContext({ school: ' A ', region: ' B ', ageBand: 'invalid' }),
    { school: 'A', region: 'B', ageBand: '' });
  const base = { title: 'Hidden event', category: '기타', startsAt: '2099-01-01T01:00:00Z',
    endsAt: '2099-01-01T02:00:00Z', originKind: 'shared' };
  const args = { saved: [], interests: new Map(), excluded: new Set(), userId: 'viewer', context: { school: 'A' },
    catalog: [
      { ...base, id: 'same', community: { school: 'A' }, sharingUserId: 'other' },
      { ...base, id: 'different', community: { school: 'B' }, sharingUserId: 'other' },
      { ...base, id: 'self', community: { school: 'A' }, sharingUserId: 'viewer' },
    ] };
  assert.deepEqual(rankRecommendations(args).map((row) => row.id), ['same']);
  assert.equal(rankRecommendations({ ...args, saved: [{ title: 'Other', startsAt: base.startsAt, endsAt: base.endsAt }] }).length, 0);
});

test('sharing API isolates personal data, enforces ownership, recommends by context and revokes', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'cue-community-'));
  Object.assign(process.env, { CUE_TEST_MODE: '1', CUE_DEMO_MODE: '0', SUPABASE_URL: '',
    SUPABASE_PUBLISHABLE_KEY: '', CUE_DB_FILE: path.join(directory, 'test.sqlite'),
    CUE_DATA_FILE: path.join(directory, 'missing.json'), CATALOG_ADMIN_TOKEN: 'admin' });
  const { server } = await import('../src/server.js');
  const { store } = await import('../src/store.js');
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const request = async (route, token, body, method = 'POST') => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, {
      method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, ...await response.json() };
  };
  try {
    const a = await request('/v1/session', null, {}), b = await request('/v1/session', null, {});
    await request('/v1/profile', a.token, { school: 'A', region: 'Seoul', ageBand: '20s' }, 'PATCH');
    await request('/v1/profile', b.token, { school: 'A' }, 'PATCH');
    const saved = await request('/v1/events', a.token, { title: 'School poster', venue: 'Auditorium',
      startsAt: '2099-01-01T01:00:00Z', endsAt: '2099-01-01T02:00:00Z', category: '기타',
      calendarId: 'private-calendar', calendarEventId: 'private-id', reminderMinutes: 60,
      locationAddress: 'private-address' });
    const route = `/v1/events/${saved.event.id}/share`;
    assert.equal((await request('/v1/recommendations', b.token, undefined, 'GET')).events.length, 0);
    assert.equal((await request(route, a.token, {})).status, 400);
    assert.equal((await request(route, b.token, { confirmPublic: true })).status, 404);
    const published = await request(route, a.token, { confirmPublic: true });
    assert.equal(published.status, 201);
    assert.equal((await request(route, a.token, { confirmPublic: true })).shared.id, published.shared.id);
    const me = await request('/v1/me', a.token, undefined, 'GET');
    assert.equal(me.saved[0].shared, true);
    const events = (await request('/v1/recommendations', b.token, undefined, 'GET')).events;
    assert.equal(events.length, 1);
    assert.equal(events[0].originKind, 'shared');
    for (const field of ['calendarId', 'calendarEventId', 'reminderMinutes', 'sharingUserId', 'community', 'share_source_event_id'])
      assert.equal(Object.hasOwn(events[0], field), false, field);
    assert.equal(events[0].locationAddress, null);
    assert.equal((await request('/v1/recommendations', a.token, undefined, 'GET')).events.length, 0);
    // Another user cannot withdraw the publisher's share.
    await request(route, b.token, undefined, 'DELETE');
    assert.equal((await request('/v1/recommendations', b.token, undefined, 'GET')).events.length, 1);
    await request('/v1/profile', a.token, { school: 'B', region: '' }, 'PATCH');
    assert.equal((await request('/v1/recommendations', b.token, undefined, 'GET')).events.length, 0);
    await request('/v1/profile', a.token, { school: 'A' }, 'PATCH');
    await request(route, a.token, undefined, 'DELETE');
    assert.equal((await request('/v1/recommendations', b.token, undefined, 'GET')).events.length, 0);
    assert.equal((await request('/v1/me', a.token, undefined, 'GET')).saved.length, 1);
    await request(route, a.token, { confirmPublic: true });
    await request(`/v1/events/${saved.event.id}`, a.token, undefined, 'DELETE');
    assert.equal((await request('/v1/recommendations', b.token, undefined, 'GET')).events.length, 0);
    const webId = '44444444-4444-4444-4444-444444444444';
    store.importCatalog([{ id: webId, title: 'AI seminar', venue: 'Online', category: '강연',
      startsAt: '2099-02-01T01:00:00Z', endsAt: '2099-02-01T02:00:00Z',
      originKind: 'web', sourceUrl: 'https://example.com/event' }]);
    await request('/v1/interactions', b.token, { eventId: webId, action: 'interested' });
    const webEvents = (await request('/v1/recommendations', b.token, undefined, 'GET')).events;
    assert.equal(webEvents[0].originKind, 'web');
    assert.equal(webEvents[0].sourceUrl, 'https://example.com/event');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    store.close();
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('cloud sharing calls authenticated RPC rather than publishing private rows directly', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ id: 'shared' }));
  };
  try {
    const cloud = new CloudStore({ id: 'user', token: 'user-token' }, { url: 'https://example.com', key: 'public-key' });
    await cloud.shareEvent('user', 'event');
    await cloud.unshareEvent('user', 'event');
    assert.ok(calls[0].url.endsWith('/rpc/cue_share_event'));
    assert.ok(calls[1].url.endsWith('/rpc/cue_unshare_event'));
    assert.ok(calls.every(({ options }) => options.headers.authorization === 'Bearer user-token'));
    assert.deepEqual(JSON.parse(calls[0].options.body), { source_id: 'event' });
  } finally { globalThis.fetch = original; }
});
