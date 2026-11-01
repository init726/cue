import test from 'node:test';
import assert from 'node:assert/strict';
import { discoverSeoulEvents, seoulCategory, seoulEvent, seoulVisit } from '../src/seoul.js';

const now = Date.parse('2026-11-02T03:00:00Z'); // 11월 2일 낮(한국)
const row = (extra) => ({ CODENAME: '콘서트', GUNAME: '강동구', TITLE: '재즈 트리오 내한공연', PLACE: '강동아트센터',
  STRTDATE: '2026-11-20 00:00:00.0', END_DATE: '2026-11-20 00:00:00.0', DATE: '2026-11-20~2026-11-20',
  PRO_TIME: '19:30', IS_FREE: '유료', USE_FEE: 'R석 77,000원', LAT: '37.55', LOT: '127.15',
  HMPG_ADDR: 'https://culture.seoul.go.kr/view.do?cultcode=1', ...extra });

test('a one-day show keeps its printed start and long runs get a visit inside opening hours', () => {
  const show = seoulEvent(row({}), now);
  assert.equal(show.startsAt, '2026-11-20T10:30:00.000Z');
  assert.equal(show.endsAt, '2026-11-20T12:30:00.000Z');
  assert.equal(show.category, '콘서트');
  assert.deepEqual(show.tags, ['서울시 문화행사', '강동구']);
  assert.equal(show.participationFee, 'R석 77,000원');
  assert.doesNotMatch(show.description, /추천 방문 시간/);
  const exhibition = seoulEvent(row({ CODENAME: '전시/미술', STRTDATE: '2026-10-01 00:00:00.0', END_DATE: '2026-12-31 00:00:00.0',
    DATE: '2026-10-01~2026-12-31', PRO_TIME: '10:00~18:00', IS_FREE: '무료' }), now);
  assert.equal(exhibition.startsAt, '2026-11-03T05:00:00.000Z', '이미 시작한 전시는 내일 14:00');
  assert.equal(exhibition.category, '미술 전시');
  assert.equal(exhibition.participationFee, '무료');
  assert.match(exhibition.description, /추천 방문 시간 14:00–16:00/);
  const lateOpen = seoulVisit(row({ STRTDATE: '2026-11-10 00:00:00.0', END_DATE: '2026-11-30 00:00:00.0', PRO_TIME: '17:00~21:00' }), now);
  assert.equal(lateOpen.startsAt, '2026-11-10T08:00:00.000Z', '문을 여는 17:00부터');
  assert.equal(seoulCategory('축제-문화/예술'), '지역 축제');
});

test('past, far-off, linkless and swapped-coordinate rows are handled', () => {
  assert.equal(seoulEvent(row({ STRTDATE: '2026-10-01 00:00:00.0', END_DATE: '2026-10-02 00:00:00.0' }), now), null);
  assert.equal(seoulEvent(row({ STRTDATE: '2027-03-01 00:00:00.0', END_DATE: '2027-03-01 00:00:00.0' }), now), null);
  assert.equal(seoulEvent(row({ HMPG_ADDR: '', ORG_LINK: 'http://insecure.example' }), now), null);
  const swapped = seoulEvent(row({ LAT: '127.15', LOT: '37.55' }), now);
  assert.deepEqual([swapped.locationLatitude, swapped.locationLongitude], [37.55, 127.15]);
  const untimed = seoulEvent(row({ PRO_TIME: '' }), now);
  assert.match(untimed.description, /정확한 시간은 안내 페이지/);
});

test('pages are read until a short page, duplicates are dropped, and API errors are explained', async () => {
  const pages = [];
  const fetchImpl = async (url) => {
    pages.push(String(url));
    const rows = pages.length === 1 ? [row({}), row({}), row({ TITLE: '다른 공연', HMPG_ADDR: 'https://culture.seoul.go.kr/view.do?cultcode=2' })] : [row({ TITLE: '마지막', HMPG_ADDR: 'https://culture.seoul.go.kr/view.do?cultcode=3' })];
    return new Response(JSON.stringify({ culturalEventInfo: { RESULT: { CODE: 'INFO-000' }, row: rows } }));
  };
  const events = await discoverSeoulEvents({ key: 'k', fetchImpl, currentTime: now, size: 3, pages: 5 });
  assert.deepEqual(events.map((event) => event.title), ['재즈 트리오 내한공연', '다른 공연', '마지막']);
  assert.match(pages[1], /culturalEventInfo\/4\/6\//);
  assert.deepEqual(await discoverSeoulEvents({ key: '', fetchImpl }), []);
  const broken = async () => new Response('<RESULT><CODE>INFO-100</CODE><MESSAGE><![CDATA[인증키가 유효하지 않습니다.]]></MESSAGE></RESULT>');
  await assert.rejects(discoverSeoulEvents({ key: 'bad', fetchImpl: broken }), /인증키가 유효하지 않습니다/);
});
