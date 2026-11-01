// 한국관광공사 TourAPI(KorService2 searchFestival2)로 전국 축제를 가져온다.
// 공공데이터포털 인증키(TOUR_API_KEY, 디코딩 키)가 없으면 아무것도 하지 않는다.
import { validateSavedEvent } from './domain.js';

const endpoint = 'https://apis.data.go.kr/B551011/KorService2/searchFestival2';
const lookaheadMs = 60 * 86400000;
const day = 86400000;

// "20261103" → 그 날 0시(한국 시각)의 UTC 밀리초.
const kstDay = (text) => {
  const match = /^(\d{4})(\d{2})(\d{2})$/.exec(String(text || ''));
  return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) - 9 * 3600000 : NaN;
};
const yyyymmdd = (ms) => new Date(ms + 9 * 3600000).toISOString().slice(0, 10).replaceAll('-', '');
const dotted = (text) => `${text.slice(0, 4)}.${Number(text.slice(4, 6))}.${Number(text.slice(6, 8))}`;

// 축제는 기간 안에서 내일 이후 첫날 14:00–16:00을 추천 방문 시간으로 쓴다(시간은 안내 페이지에서 확인).
export function tourEvent(item, currentTime = Date.now()) {
  const first = kstDay(item.eventstartdate), last = kstDay(item.eventenddate);
  const title = String(item.title || '').trim();
  const venue = [item.addr1, item.addr2].map((part) => String(part || '').trim()).filter(Boolean).join(' ');
  if (!Number.isFinite(first) || !Number.isFinite(last) || last < first || !title || !venue) return null;
  const tomorrow = kstDay(yyyymmdd(currentTime + day));
  const visitDay = Math.max(first, tomorrow);
  if (visitDay > last || visitDay - currentTime > lookaheadMs) return null;
  const latitude = Number(item.mapy), longitude = Number(item.mapx);
  const province = String(item.addr1 || '').trim().split(/\s+/)[0] || null;
  try {
    return validateSavedEvent({
      title, venue, category: '지역 축제',
      startsAt: new Date(visitDay + 14 * 3600000).toISOString(),
      endsAt: new Date(visitDay + 16 * 3600000).toISOString(),
      description: `기간 ${dotted(item.eventstartdate)} ~ ${dotted(item.eventenddate)} · 추천 방문 시간 14:00–16:00 · 정확한 시간과 프로그램은 축제 안내에서 확인해 주세요.` +
        (item.tel ? ` · 문의 ${String(item.tel).slice(0, 40)}` : ''),
      tags: ['전국 축제', province].filter(Boolean),
      locationLatitude: Number.isFinite(latitude) && latitude > 30 ? latitude : null,
      locationLongitude: Number.isFinite(longitude) && longitude > 120 ? longitude : null,
      // 축제 상세 주소는 별도 조회가 필요해 대한민국 구석구석 검색 결과로 연결한다.
      sourceUrl: `https://korean.visitkorea.or.kr/search/search_list.do?keyword=${encodeURIComponent(title)}`,
    });
  } catch {
    return null;
  }
}

// 오늘 이후 진행 중이거나 시작하는 축제를 한 번에 최대 500건씩 두 쪽 읽는다.
export async function discoverTourFestivals({ key = process.env.TOUR_API_KEY, fetchImpl = fetch, currentTime = Date.now(), pages = 2, size = 500 } = {}) {
  if (!key) return [];
  const events = [], seen = new Set();
  for (let page = 1; page <= pages; page += 1) {
    const url = new URL(endpoint);
    for (const [name, value] of Object.entries({ serviceKey: key, MobileOS: 'ETC', MobileApp: 'Cue', _type: 'json',
      eventStartDate: yyyymmdd(currentTime), numOfRows: String(size), pageNo: String(page), arrange: 'C' })) {
      url.searchParams.set(name, value);
    }
    const response = await fetchImpl(url, { signal: AbortSignal.timeout(20000) });
    const text = await response.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      // 키 오류는 XML로 온다.
      throw new Error(`TourAPI 오류: ${/<returnAuthMsg>([^<]*)/.exec(text)?.[1] || /<resultMsg>([^<]*)/.exec(text)?.[1] || text.slice(0, 80)}`);
    }
    const header = body.response?.header;
    if (header?.resultCode && header.resultCode !== '0000') throw new Error(`TourAPI 오류: ${header.resultMsg}`);
    const raw = body.response?.body?.items?.item;
    const items = Array.isArray(raw) ? raw : raw ? [raw] : [];
    for (const item of items) {
      const event = tourEvent(item, currentTime);
      if (event && !seen.has(event.title)) {
        seen.add(event.title);
        events.push(event);
      }
    }
    if (items.length < size) break;
  }
  return events;
}
