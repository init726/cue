import test from 'node:test';
import assert from 'node:assert/strict';
import { discoveryTopic, discoveryTopics, verifiedDiscoveries } from '../src/discovery.js';
import { classifyEvent } from '../src/classification.js';
import { rankRecommendations } from '../src/personalization.js';

const currentTime = Date.parse('2026-09-20T00:00:00+09:00');
const detail = 'https://sema.seoul.go.kr/kr/whatson/exhibition/detail?exNo=1579618';
const candidate = { title: '최혜련 개인전', category: '미술 전시', tags: ['설치미술'],
  startsAt: '2026-09-23T14:00:00+09:00', endsAt: '2026-09-23T16:00:00+09:00',
  venue: '서울', description: '추천 방문 시간', sourceUrl: detail };

test('only sourced, future event detail pages enter discovery catalog', () => {
  const response = {
    status: 'completed',
    output: [
      { type: 'web_search_call', action: { sources: [{ url: detail }] } },
      { type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ events: [
        candidate,
        { ...candidate, title: '출처 없는 행사', sourceUrl: 'https://example.com/event' },
        { ...candidate, title: '지난 행사', startsAt: '2026-09-19T14:00:00+09:00' },
      ] }) }] },
    ],
  };
  const events = verifiedDiscoveries(response, currentTime);
  assert.equal(events.length, 1);
  assert.equal(events[0].sourceUrl, detail);
  assert.equal(events[0].category, '미술 전시');
});

test('broad saved category matches verified finer exhibition category', () => {
  assert.equal(discoveryTopic(new Map([['domain:미술', 8], ['domain:기타', 20]])), '미술 전시');
  const results = rankRecommendations({
    catalog: [{ id: 'detail', ...candidate }], saved: [],
    interests: new Map([['domain:미술', 8]]), excluded: new Set(), currentTime,
  });
  assert.equal(results.length, 1);
  assert.ok(results[0].score > 0);
});

test('discovery rotates through the top interests instead of only the strongest one', () => {
  const topics = discoveryTopics(new Map([['domain:AI', 5], ['domain:음악', 4], ['domain:소프트웨어', 3], ['domain:교육', 1]]));
  assert.deepEqual(topics, [{ topic: '기술', subject: 'AI·소프트웨어' }, { topic: '음악', subject: '음악' }]);
  assert.deepEqual(discoveryTopics(new Map([['domain:문화', 2]])).map((item) => item.topic), ['전시', '공연']);
  assert.deepEqual(discoveryTopics(new Map([['domain:기타', 9], ['domain:미술', -1]])), []);
});

test('saved stage shows build a performance interest that matches theatre recommendations', () => {
  assert.deepEqual(classifyEvent({ title: '뮤지컬 레미제라블', category: '뮤지컬' }).domains, ['공연']);
  assert.deepEqual(classifyEvent({ title: '햄릿', category: '연극' }).domains, ['공연', '문화']);
  const play = { id: 'play', title: '연극 갈매기', category: '연극', domains: ['공연', '문화'], tags: ['연극'],
    startsAt: '2026-09-25T19:00:00+09:00', endsAt: '2026-09-25T21:00:00+09:00', venue: '대학로' };
  const results = rankRecommendations({ catalog: [play], saved: [], excluded: new Set(), currentTime,
    interests: new Map([['domain:공연', 4], ['domain:AI', 6]]) });
  assert.equal(results.length, 1);
  assert.equal(discoveryTopics(new Map([['domain:공연', 4]]))[0].topic, '공연');
});

test('specific title words override a noisy AI category and tags', () => {
  const result = classifyEvent({
    title: '성남동 커피페스티벌', category: '음악', domains: ['음악'],
    tags: ['버스킹', '라이브 공연'], description: '커피 체험과 음악 공연',
  });
  assert.equal(result.category, '커피·와인');
  assert.deepEqual(result.domains, ['음식']);
});
