import test from 'node:test';
import assert from 'node:assert/strict';
import { discoverKopisPerformances, nextShowing, parseRuntime, parseShowtimes } from '../src/kopis.js';
import { discoverCatalogEvents } from '../src/discovery.js';

// 2026-10-21(수) 정오 KST
const currentTime = Date.parse('2026-10-21T12:00:00+09:00');
const list = (ids) => `<?xml version="1.0" encoding="UTF-8"?><dbs>${ids.map((id) => `<db><mt20id>${id}</mt20id></db>`).join('')}</dbs>`;
const detail = (id, extra = {}) => {
  const fields = { mt20id: id, prfnm: `공연 ${id}`, prfpdfrom: '2026.10.01', prfpdto: '2026.11.30',
    fcltynm: '예술의전당 [서울] (콘서트홀)', prfruntime: '1시간 40분', pcseguidance: 'R석 50,000원',
    dtguidance: '토요일 ~ 일요일(15:00,19:00)', prfstate: '공연중', ...extra };
  return `<dbs><db>${Object.entries(fields).map(([key, value]) => `<${key}>${value}</${key}>`).join('')}</db></dbs>`;
};

test('KOPIS weekday ranges and runtimes become the earliest showtime per day', () => {
  const times = parseShowtimes('화요일 ~ 금요일(20:00), 토요일 ~ 일요일(15:00,19:00), HOL(15:00)');
  assert.equal(times.get(2), 20 * 60);
  assert.equal(times.get(5), 20 * 60);
  assert.equal(times.get(6), 15 * 60);
  assert.equal(times.get(0), 15 * 60);
  assert.equal(times.has(1), false);
  assert.equal(parseRuntime('1시간 40분'), 100);
  assert.equal(parseRuntime('100분'), 100);
  assert.equal(parseRuntime(''), 120);
});

test('the next KOPIS showing starts tomorrow or later and stays within the run', () => {
  const run = { prfpdfrom: '2026.10.01', prfpdto: '2026.11.30', prfruntime: '1시간 40분', dtguidance: '토요일(15:00)' };
  assert.deepEqual(nextShowing(run, currentTime), { startsAt: '2026-10-24T15:00:00+09:00', endsAt: '2026-10-24T16:40:00+09:00' });
  assert.equal(nextShowing({ ...run, dtguidance: '수요일(19:00)', prfpdto: '2026.10.21' }, currentTime), null);
  assert.equal(nextShowing({ ...run, dtguidance: 'HOL(15:00)' }, currentTime), null);
});

test('KOPIS performances use official detail pages and skip finished or unscheduled shows', async () => {
  const requested = [];
  const fetchImpl = async (url) => {
    requested.push(url);
    if (url.includes('shcate=CCCA')) return new Response(list(['PF1', 'PF2']));
    if (url.includes('shcate=')) return new Response(list(['PF3']));
    if (url.includes('/PF2?')) return new Response(detail('PF2', { prfstate: '공연완료' }));
    if (url.includes('/PF3?')) return new Response(detail('PF3', { dtguidance: '' }));
    return new Response(detail('PF1'));
  };
  const events = await discoverKopisPerformances('음악', { fetchImpl, currentTime, serviceKey: 'key' });
  assert.equal(events.length, 1);
  assert.equal(events[0].title, '공연 PF1');
  assert.equal(events[0].category, '클래식');
  assert.deepEqual(events[0].domains, ['음악', '문화']);
  assert.equal(events[0].startsAt, '2026-10-24T06:00:00.000Z');
  assert.equal(events[0].sourceUrl, 'https://kopis.or.kr/por/db/pblprfr/pblprfrView.do?menuId=MNU_00020&mt20Id=PF1');
  assert.ok(requested.every((url) => url.startsWith('https://kopis.or.kr/openApi/restful/pblprfr')));
  assert.ok(requested.filter((url) => url.includes('shcate=')).every((url) => url.includes('signgucode=11') &&
    url.includes('stdate=20261022') && url.includes('eddate=20261120')));
});

test('KOPIS errors are raised and an unset key skips the API', async () => {
  const fetchImpl = async () => new Response('<dbs><db><returncode>02</returncode><errmsg>SERVICE KEY IS NOT REGISTERED ERROR</errmsg></db></dbs>');
  await assert.rejects(discoverKopisPerformances('공연', { fetchImpl, currentTime, serviceKey: 'bad' }), /SERVICE KEY/);
  assert.deepEqual(await discoverKopisPerformances('공연', { fetchImpl, currentTime, serviceKey: '' }), []);
});

test('performance discovery falls back to web search when KOPIS fails', async (t) => {
  t.mock.method(console, 'error', () => {});
  const previous = process.env.KOPIS_API_KEY;
  process.env.KOPIS_API_KEY = 'bad';
  t.after(() => { if (previous == null) delete process.env.KOPIS_API_KEY; else process.env.KOPIS_API_KEY = previous; });
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(String(url));
    if (String(url).includes('kopis.or.kr')) return new Response('', { status: 503 });
    return Response.json({ status: 'completed', output: [] });
  };
  assert.deepEqual(await discoverCatalogEvents('공연', { fetchImpl, currentTime }), []);
  assert.ok(calls.some((url) => url.includes('kopis.or.kr')));
  assert.ok(calls.some((url) => url === 'https://api.openai.com/v1/responses'));
});

test('exhibition discovery merges SEMA with other official museums found by search', async () => {
  const sema = 'https://sema.seoul.go.kr/kr/whatson/exhibition/detail?exNo=1';
  const mmca = 'https://www.mmca.go.kr/exhibitions/exhibitionsDetail.do?exhId=2';
  const semaListing = '<div id="dv_1" data-ex-menu-div="EXM01"><strong class="o_h1">시립 전시</strong></div>';
  const semaDetail = `<div class="o_h1">전시장소</div><p>서울시립미술관 서소문본관</p>
    <div class="o_h1">전시기간</div><p>2026.10.01~2026.12.31</p>`;
  const searched = { title: '국립 전시', category: '미술 전시', format: '전시', domains: ['미술'], tags: [],
    startsAt: '2026-10-23T14:00:00+09:00', endsAt: '2026-10-23T16:00:00+09:00',
    venue: '국립현대미술관 서울', description: '추천 방문 시간', sourceUrl: mmca };
  let prompt = '';
  const fetchImpl = async (url, options) => {
    if (String(url).includes('/landing?')) return new Response(semaListing);
    if (String(url).includes('sema.seoul.go.kr')) return new Response(semaDetail);
    prompt = JSON.parse(options.body).input;
    return Response.json({ status: 'completed', output: [
      { type: 'web_search_call', action: { sources: [{ url: mmca }] } },
      { type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ events: [searched] }) }] },
    ] });
  };
  const events = await discoverCatalogEvents('미술 전시', { fetchImpl, currentTime });
  assert.deepEqual(events.map((event) => event.sourceUrl).sort(), [mmca, sema].sort());
  assert.ok(prompt.includes('site:mmca.go.kr') && !prompt.includes('sema.seoul.go.kr'));
});
