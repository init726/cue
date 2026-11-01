import test from 'node:test';
import assert from 'node:assert/strict';
import { searchPlaces, placeMapUrl } from '../src/places.js';
import { validateSavedEvent } from '../src/domain.js';
import { placeFromRow } from '../src/community.js';

test('kakao keyword results become verified place candidates and the key stays on the server', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), auth: options.headers.authorization });
    return new Response(JSON.stringify({ documents: [
      { id: '8217196', place_name: '서울시립미술관 서소문본관', road_address_name: '서울 중구 덕수궁길 61', address_name: '서울 중구 서소문동 37',
        category_name: '문화,예술 > 문화시설 > 미술관', x: '126.973456', y: '37.564123', distance: '420' },
      { id: 'not-a-number', place_name: '이상한 결과', x: '1', y: '1' },
    ] }));
  };
  const original = process.env.KAKAO_REST_API_KEY;
  process.env.KAKAO_REST_API_KEY = 'test-key';
  try {
    const places = await searchPlaces('서울시립미술관', { latitude: 37.56, longitude: 126.97, fetchImpl });
    assert.deepEqual(places, [{ provider: 'kakao', id: '8217196', name: '서울시립미술관 서소문본관',
      address: '서울 중구 덕수궁길 61', category: '미술관', latitude: 37.564123, longitude: 126.973456,
      distanceMeters: 420, mapUrl: 'https://place.map.kakao.com/8217196' }]);
    assert.match(calls[0].url, /query=%EC%84%9C%EC%9A%B8/);
    assert.match(calls[0].url, /y=37.56&x=126.97/);
    assert.equal(calls[0].auth, 'KakaoAK test-key');
    assert.deepEqual(await searchPlaces('a', { fetchImpl }), [], '한 글자는 검색하지 않는다');
    delete process.env.KAKAO_REST_API_KEY;
    assert.deepEqual(await searchPlaces('서울시립미술관', { fetchImpl }), [], '키가 없으면 검색하지 않는다');
    assert.equal(calls.length, 1);
  } finally {
    if (original === undefined) delete process.env.KAKAO_REST_API_KEY; else process.env.KAKAO_REST_API_KEY = original;
  }
});

test('saved events keep a place link only when sent, and a typed venue can drop it', () => {
  const base = { title: '전시', venue: '서울시립미술관', startsAt: '2027-01-01T01:00:00Z', endsAt: '2027-01-01T02:00:00Z' };
  assert.equal(Object.hasOwn(validateSavedEvent(base), 'placeId'), false);
  const linked = validateSavedEvent({ ...base, placeProvider: 'kakao', placeId: '8217196', placeCategory: '미술관' });
  assert.deepEqual([linked.placeProvider, linked.placeId, linked.placeCategory], ['kakao', '8217196', '미술관']);
  const dropped = validateSavedEvent({ ...base, placeId: null });
  assert.deepEqual([dropped.placeProvider, dropped.placeId], [null, null]);
  assert.equal(validateSavedEvent({ ...base, placeProvider: 'kakao', placeId: '../x' }).placeId, null);
  assert.equal(placeMapUrl('kakao', '12'), 'https://place.map.kakao.com/12');
  assert.equal(placeMapUrl('other', '12'), null);
  assert.equal(placeFromRow({ location_name: '집' }), null);
  assert.equal(placeFromRow({ place_provider: 'kakao', place_id: '12', location_name: '미술관', location_address: '주소', place_category: '미술관' }).mapUrl,
    'https://place.map.kakao.com/12');
});

test('sharing a verified place reveals its public address, an unverified venue does not', async () => {
  const fs = await import('node:fs/promises'), os = await import('node:os'), path = await import('node:path');
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'cue-places-'));
  Object.assign(process.env, { CUE_TEST_MODE: '1', CUE_DEMO_MODE: '0', SUPABASE_URL: '', SUPABASE_PUBLISHABLE_KEY: '',
    CUE_DB_FILE: path.join(directory, 'test.sqlite'), CUE_DATA_FILE: path.join(directory, 'missing.json') });
  const { server } = await import('../src/server.js');
  const { store } = await import('../src/store.js');
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const request = async (route, token, body, method = 'POST') => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, {
      method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, ...await response.json() };
  };
  try {
    const a = await request('/v1/session', null, {}), b = await request('/v1/session', null, {});
    await request('/v1/profile', a.token, { school: 'P' }, 'PATCH');
    await request('/v1/profile', b.token, { school: 'P' }, 'PATCH');
    const save = (title, extra) => request('/v1/events', a.token, { title, category: '전시',
      startsAt: '2099-03-01T01:00:00Z', endsAt: '2099-03-01T02:00:00Z', locationAddress: '서울 중구 덕수궁길 61',
      locationLatitude: 37.564123, locationLongitude: 126.973456, ...extra });
    const verified = await save('확인된 전시', { venue: '서울시립미술관', placeProvider: 'kakao', placeId: '8217196', placeCategory: '미술관' });
    const typed = await save('직접 적은 모임', { venue: '우리집 거실' });
    assert.equal(verified.event.placeId, '8217196');
    assert.equal((await request('/v1/places?q=미술관', b.token, undefined, 'GET')).enabled, false);
    for (const saved of [verified, typed]) await request(`/v1/events/${saved.event.id}/share`, a.token, { confirmPublic: true });
    const events = (await request('/v1/recommendations', b.token, undefined, 'GET')).events;
    const place = events.find((event) => event.title === '확인된 전시').place;
    assert.deepEqual(place, { provider: 'kakao', id: '8217196', name: '서울시립미술관', address: '서울 중구 덕수궁길 61',
      category: '미술관', mapUrl: 'https://place.map.kakao.com/8217196' });
    const home = events.find((event) => event.title === '직접 적은 모임');
    assert.equal(home.place, null);
    assert.equal(home.locationAddress, null);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    store.close();
    await fs.rm(directory, { recursive: true, force: true });
  }
});
