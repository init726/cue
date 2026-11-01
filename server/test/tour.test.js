import test from 'node:test';
import assert from 'node:assert/strict';
import { discoverTourFestivals, tourEvent } from '../src/tour.js';

const now = Date.parse('2026-11-02T03:00:00Z');
const item = (extra) => ({ title: '청송사과축제', addr1: '경상북도 청송군 청송읍', addr2: '용전천 일원',
  eventstartdate: '20261029', eventenddate: '20261108', mapx: '129.0567', mapy: '36.4359', tel: '054-870-6240', contentid: '1', ...extra });

test('a running festival gets a visit from tomorrow with its period and province', () => {
  const event = tourEvent(item({}), now);
  assert.equal(event.category, '지역 축제');
  assert.equal(event.startsAt, '2026-11-03T05:00:00.000Z');
  assert.equal(event.venue, '경상북도 청송군 청송읍 용전천 일원');
  assert.deepEqual(event.tags, ['전국 축제', '경상북도']);
  assert.match(event.description, /기간 2026.10.29 ~ 2026.11.8 · 추천 방문 시간 14:00–16:00/);
  assert.deepEqual([event.locationLatitude, event.locationLongitude], [36.4359, 129.0567]);
  assert.match(event.sourceUrl, /^https:\/\/korean\.visitkorea\.or\.kr\/search\/search_list\.do\?keyword=/);
  assert.equal(tourEvent(item({ eventenddate: '20261101' }), now), null, '끝난 축제');
  assert.equal(tourEvent(item({ eventstartdate: '20270301', eventenddate: '20270302' }), now), null, '60일 밖');
});

test('festival pages are read with the key and key errors are explained', async () => {
  const asked = [];
  const fetchImpl = async (url) => {
    asked.push(new URL(url));
    return new Response(JSON.stringify({ response: { header: { resultCode: '0000' },
      body: { items: { item: [item({}), item({}), item({ title: '구미라면축제', addr1: '경상북도 구미시' })] } } } }));
  };
  const events = await discoverTourFestivals({ key: 'k', fetchImpl, currentTime: now });
  assert.deepEqual(events.map((event) => event.title), ['청송사과축제', '구미라면축제']);
  assert.equal(asked[0].searchParams.get('eventStartDate'), '20261102');
  assert.equal(asked[0].searchParams.get('_type'), 'json');
  assert.deepEqual(await discoverTourFestivals({ key: '' }), []);
  const xml = async () => new Response('<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg></cmmMsgHeader></OpenAPI_ServiceResponse>');
  await assert.rejects(discoverTourFestivals({ key: 'bad', fetchImpl: xml }), /SERVICE_KEY_IS_NOT_REGISTERED_ERROR/);
});
