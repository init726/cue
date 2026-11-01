import test from 'node:test';
import assert from 'node:assert/strict';
import { peerCounts, similarPeople } from '../src/peers.js';
import { rankRecommendations } from '../src/personalization.js';

test('only similar people count and lone saves stay hidden', () => {
  const profiles = new Map([
    ['a', { age_band: '20s' }], ['b', { region_latitude: 37.56, region_longitude: 126.98 }],
    ['c', { favorite_topics: ['음악'] }], ['d', { age_band: '40plus' }], ['e', { school: 'X' }],
  ]);
  const links = [['a', 'jazz'], ['b', 'jazz'], ['c', 'jazz'], ['d', 'jazz'], ['me', 'jazz'], ['a', 'solo'], ['e', 'art'], ['d', 'art']]
    .map(([userId, eventId]) => ({ userId, eventId }));
  const viewer = { age_band: '20s', region_latitude: 37.57, region_longitude: 126.97, favorite_topics: ['음악'] };
  const counts = peerCounts({ links, profiles, viewerId: 'me', viewer, minimum: 2 });
  assert.deepEqual([...counts], [['jazz', { count: 3, similar: true }]], '같은 연령대·근처·같은 관심 3명, 혼자 저장한 행사는 숨김');
  const anyone = peerCounts({ links, profiles, viewerId: 'me', viewer: {}, minimum: 2 });
  assert.deepEqual(anyone.get('art'), { count: 2, similar: false }, '내 정보가 없으면 전체 사용자 수로 센다');
  assert.equal(similarPeople({ school: '', ageBand: '', regionLatitude: null, regionLongitude: null, favoriteTopics: [] },
    { school: '', ageBand: '', favoriteTopics: [] }), false);
});

test('peer saves and my area get their own sections ahead of interests, and festivals lead my area', () => {
  const at = (day) => ({ startsAt: `2099-02-${day}T05:00:00Z`, endsAt: `2099-02-${day}T07:00:00Z` });
  const results = rankRecommendations({
    catalog: [
      { ...at(10), id: 'peer', title: '인디 공연', domains: ['음악'], locationLatitude: 35.1, locationLongitude: 129 },
      { ...at(11), id: 'near-talk', title: '동네 강연', domains: ['교육'], locationLatitude: 37.57, locationLongitude: 126.98 },
      { ...at(12), id: 'near-fest', title: '정동 가을 축제', domains: ['문화'], locationLatitude: 37.566, locationLongitude: 126.975 },
      { ...at(13), id: 'far-music', title: '부산 재즈 페스티벌', category: '음악 페스티벌', domains: ['음악'], locationLatitude: 35.1, locationLongitude: 129.1 },
    ],
    saved: [], interests: new Map([['domain:음악', 4]]), excluded: new Set(), currentTime: Date.parse('2099-01-01T00:00:00Z'),
    context: { regionLatitude: 37.56, regionLongitude: 126.98 },
    peerCounts: new Map([['peer', { count: 3, similar: true }]]),
  });
  assert.deepEqual(results.map((event) => [event.id, event.section]),
    [['peer', 'peers'], ['near-fest', 'local'], ['near-talk', 'local'], ['far-music', 'interest']]);
  assert.match(results[0].reason, /비슷한 환경의 3명/);
  assert.match(results[1].reason, /내 지역 약 1km · 축제/);
});
