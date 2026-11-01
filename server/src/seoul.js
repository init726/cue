// 서울 열린데이터광장 '서울시 문화행사 정보'(culturalEventInfo)에서 다가오는 행사를 가져온다.
// 키(SEOUL_OPEN_API_KEY)가 없으면 아무것도 하지 않는다. 공개 API라 HTTP 주소만 제공된다.
import { validateSavedEvent } from './domain.js';

const pageSize = 1000;
const lookaheadMs = 60 * 86400000;
const day = 86400000;

const categoryByCode = {
  '전시/미술': '미술 전시', 콘서트: '콘서트', 클래식: '클래식', '독주/독창회': '클래식', 국악: '국악',
  '뮤지컬/오페라': '뮤지컬', 연극: '연극', 무용: '무용', 영화: '영화·상영회', '교육/체험': '교육',
};
export const seoulCategory = (code) =>
  categoryByCode[code] || (String(code || '').startsWith('축제') ? '지역 축제' : '기타');

// "2026-12-24 00:00:00.0" → 그 날 0시(한국 시각)의 UTC 밀리초.
const kstDay = (text) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(text || ''));
  return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) - 9 * 3600000 : NaN;
};
const at = (dayMs, minutes) => new Date(dayMs + minutes * 60000).toISOString();
const https = (url) => (/^https:\/\//.test(String(url || '')) ? String(url) : null);

// 행사 기간과 운영 시간(PRO_TIME)으로 캘린더에 넣을 방문 시간을 정한다.
// 하루 공연은 적힌 시작 시각을, 여러 날 열리는 전시·축제는 내일 이후 첫날의 추천 방문 시간(14:00–16:00)을 쓴다.
export function seoulVisit(row, currentTime = Date.now()) {
  const first = kstDay(row.STRTDATE), last = kstDay(row.END_DATE);
  if (!Number.isFinite(first) || !Number.isFinite(last) || last < first) return null;
  const tomorrow = kstDay(new Date(currentTime + 9 * 3600000 + day).toISOString());
  const visitDay = Math.max(first, tomorrow);
  if (visitDay > last || visitDay - currentTime > lookaheadMs) return null;
  const times = [...String(row.PRO_TIME || '').matchAll(/(\d{1,2}):(\d{2})/g)]
    .map((match) => Number(match[1]) * 60 + Number(match[2])).filter((minutes) => minutes < 24 * 60);
  const range = times.length >= 2 && times[1] > times[0];
  if (last === first || (times.length === 1 && !range)) {
    if (!times.length) return { startsAt: at(visitDay, 14 * 60), endsAt: at(visitDay, 16 * 60), flexible: true, timeKnown: false };
    const end = range ? times[1] : times[0] + 120;
    return { startsAt: at(visitDay, times[0]), endsAt: at(visitDay, end), flexible: false, timeKnown: true };
  }
  // 운영 시간 안에서 오후 2시에 가장 가깝게 두 시간 머무는 시간을 고른다.
  const open = range ? times[0] : 10 * 60, close = range ? times[1] : 18 * 60;
  const start = Math.min(Math.max(14 * 60, open), Math.max(open, close - 120));
  return { startsAt: at(visitDay, start), endsAt: at(visitDay, Math.min(close, start + 120)), flexible: true, timeKnown: range };
}

export function seoulEvent(row, currentTime = Date.now()) {
  const visit = seoulVisit(row, currentTime);
  const title = String(row.TITLE || '').trim(), venue = String(row.PLACE || '').trim();
  const sourceUrl = https(row.HMPG_ADDR) || https(row.ORG_LINK);
  if (!visit || !title || !venue || !sourceUrl) return null;
  let latitude = Number(row.LAT), longitude = Number(row.LOT);
  // 일부 행은 위도·경도가 뒤바뀌어 온다.
  if (latitude > 90 && longitude < 90) [latitude, longitude] = [longitude, latitude];
  const clock = (iso) => new Date(Date.parse(iso) + 9 * 3600000).toISOString().slice(11, 16);
  const summary = String(row.PROGRAM || row.ETC_DESC || '').replace(/\s+/g, ' ').trim().slice(0, 300);
  const notes = [
    `기간 ${String(row.DATE || '').replace('~', ' ~ ')}`,
    row.PRO_TIME ? `시간 ${String(row.PRO_TIME).trim().slice(0, 60)}` : null,
    visit.flexible ? `추천 방문 시간 ${clock(visit.startsAt)}–${clock(visit.endsAt)}` : null,
    visit.timeKnown ? null : '정확한 시간은 안내 페이지에서 확인해 주세요.',
    row.USE_TRGT ? `대상 ${String(row.USE_TRGT).trim().slice(0, 60)}` : null,
  ].filter(Boolean).join(' · ');
  try {
    return validateSavedEvent({
      title, venue, startsAt: visit.startsAt, endsAt: visit.endsAt,
      category: seoulCategory(row.CODENAME),
      description: [summary, notes].filter(Boolean).join('\n\n').slice(0, 1000),
      tags: ['서울시 문화행사', row.GUNAME, row.IS_FREE === '무료' ? '무료' : null,
        row.THEMECODE && row.THEMECODE !== '기타' ? row.THEMECODE : null].filter(Boolean),
      participationFee: row.IS_FREE === '무료' ? '무료' : String(row.USE_FEE || '').trim().slice(0, 100) || '유료',
      locationLatitude: latitude, locationLongitude: longitude, sourceUrl,
    });
  } catch {
    return null;
  }
}

// 최근 등록된 순서로 두 쪽(2,000건)을 읽어 앞으로 60일 안에 갈 수 있는 행사만 돌려준다.
export async function discoverSeoulEvents({ key = process.env.SEOUL_OPEN_API_KEY, fetchImpl = fetch, currentTime = Date.now(), pages = 2, size = pageSize } = {}) {
  if (!key) return [];
  const events = [], seen = new Set();
  for (let page = 0; page < pages; page += 1) {
    const from = page * size + 1, to = from + size - 1;
    const response = await fetchImpl(`http://openapi.seoul.go.kr:8088/${encodeURIComponent(key)}/json/culturalEventInfo/${from}/${to}/`,
      { signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw new Error(`서울시 문화행사 API 응답 ${response.status}`);
    // 키가 틀리거나 한도를 넘으면 JSON 대신 XML 오류를 보낸다.
    const text = await response.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      throw new Error(`서울시 문화행사 API 오류: ${/<MESSAGE><!\[CDATA\[([^\]]*)/.exec(text)?.[1] || text.slice(0, 80)}`);
    }
    if (body.RESULT?.CODE && body.RESULT.CODE !== 'INFO-000') throw new Error(`서울시 문화행사 API 오류: ${body.RESULT.MESSAGE}`);
    const rows = body.culturalEventInfo?.row || [];
    for (const row of rows) {
      const event = seoulEvent(row, currentTime);
      if (event && !seen.has(event.sourceUrl)) {
        seen.add(event.sourceUrl);
        events.push(event);
      }
    }
    if (rows.length < size) break;
  }
  return events;
}
