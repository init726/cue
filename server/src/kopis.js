import { validateSavedEvent } from './domain.js';

// 공연예술통합전산망(KOPIS) 공식 API. 서비스 키는 KOPIS_API_KEY 환경변수에만 둔다.
const apiBase = 'https://kopis.or.kr/openApi/restful/pblprfr';
const detailPage = (id) => `https://kopis.or.kr/por/db/pblprfr/pblprfrView.do?menuId=MNU_00020&mt20Id=${id}`;
const seoul = '11';
const lookAheadDays = 30;
const genres = {
  음악: [{ code: 'CCCA', category: '클래식' }, { code: 'CCCD', category: '콘서트' }, { code: 'CCCC', category: '음악', tag: '국악' }],
  공연: [{ code: 'AAAA', category: '연극' }, { code: 'GGGA', category: '뮤지컬' }, { code: 'BBBC', category: '무용' }, { code: 'BBBE', category: '무용' }],
};
const weekdays = '일월화수목금토';
const entities = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'" };
const plain = (value) => String(value || '').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
  .replace(/&(amp|lt|gt|quot|apos|#39);/g, (entity) => entities[entity]).replace(/\s+/g, ' ').trim();
const field = (xml, tag) => plain(xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`))?.[1]);
const records = (xml) => [...xml.matchAll(/<db>([\s\S]*?)<\/db>/g)].map(([, body]) => body);
const day = (value) => value.match(/^(\d{4})\.(\d\d)\.(\d\d)$/)?.slice(1).join('-') || null;
const compact = (date) => date.replaceAll('-', '');

function kstDate(currentTime, offset) {
  const date = new Date(currentTime + 9 * 3600000);
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() + offset);
  return date;
}

// "화요일 ~ 금요일(20:00), 토요일(15:00,19:00)"을 요일별 첫 공연 시각(분)으로 바꾼다. HOL(공휴일)은 날짜를 알 수 없어 건너뛴다.
export function parseShowtimes(guidance) {
  const byWeekday = new Map();
  for (const [, from, to, times] of String(guidance || '').matchAll(/([월화수목금토일])요일(?:\s*~\s*([월화수목금토일])요일)?\s*\(([^)]*)\)/g)) {
    const first = times.match(/(\d{1,2}):(\d\d)/);
    if (!first) continue;
    const minutes = Number(first[1]) * 60 + Number(first[2]);
    const end = weekdays.indexOf(to || from);
    for (let index = weekdays.indexOf(from); ; index = (index + 1) % 7) {
      if (!byWeekday.has(index) || byWeekday.get(index) > minutes) byWeekday.set(index, minutes);
      if (index === end) break;
    }
  }
  return byWeekday;
}

export function parseRuntime(value) {
  const hours = Number(String(value || '').match(/(\d+)\s*시간/)?.[1] || 0);
  const minutes = Number(String(value || '').match(/(\d+)\s*분/)?.[1] || 0);
  const total = hours * 60 + minutes;
  return total >= 10 && total <= 600 ? total : 120;
}

// 공연 기간과 요일별 시각에서 내일 이후 가장 가까운 회차를 고른다.
export function nextShowing(detail, currentTime) {
  const first = day(detail.prfpdfrom);
  const last = day(detail.prfpdto);
  const showtimes = parseShowtimes(detail.dtguidance);
  if (!first || !last || !showtimes.size) return null;
  for (let offset = 1; offset <= lookAheadDays; offset += 1) {
    const date = kstDate(currentTime, offset);
    const value = date.toISOString().slice(0, 10);
    if (value < first || value > last || !showtimes.has(date.getUTCDay())) continue;
    const start = showtimes.get(date.getUTCDay());
    const end = start + parseRuntime(detail.prfruntime);
    if (end >= 24 * 60) continue;
    const clock = (minutes) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
    return { startsAt: `${value}T${clock(start)}:00+09:00`, endsAt: `${value}T${clock(end)}:00+09:00` };
  }
  return null;
}

async function kopisXml(fetchImpl, url) {
  const response = await fetchImpl(url, { signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw new Error(`KOPIS 요청에 실패했습니다. (${response.status})`);
  const xml = await response.text();
  const error = field(xml, 'returncode');
  if (error && error !== '00') throw new Error(`KOPIS 오류: ${field(xml, 'errmsg') || error}`);
  return xml;
}

export async function discoverKopisPerformances(family, { fetchImpl = fetch, currentTime = Date.now(), serviceKey = process.env.KOPIS_API_KEY } = {}) {
  if (!serviceKey || !genres[family]) return [];
  const service = encodeURIComponent(serviceKey);
  const range = `stdate=${compact(kstDate(currentTime, 1).toISOString().slice(0, 10))}` +
    `&eddate=${compact(kstDate(currentTime, lookAheadDays).toISOString().slice(0, 10))}`;
  const lists = await Promise.all(genres[family].map(async (genre) => {
    const xml = await kopisXml(fetchImpl, `${apiBase}?service=${service}&${range}&cpage=1&rows=6&shcate=${genre.code}&signgucode=${seoul}`);
    return records(xml).map((body) => ({ id: field(body, 'mt20id'), genre })).filter((item) => /^PF\d+$/.test(item.id));
  }));
  // 장르마다 번갈아 골라 한 장르만 채워지지 않게 한다.
  const picked = [];
  const ids = new Set();
  for (let round = 0; picked.length < 12 && lists.some((list) => list[round]); round += 1) {
    for (const list of lists) {
      const item = list[round];
      if (item && !ids.has(item.id) && picked.length < 12) { ids.add(item.id); picked.push(item); }
    }
  }
  const details = await Promise.all(picked.map(async (item) => {
    try {
      const body = records(await kopisXml(fetchImpl, `${apiBase}/${item.id}?service=${service}`))[0];
      if (!body) return null;
      const detail = Object.fromEntries(['prfnm', 'prfpdfrom', 'prfpdto', 'fcltynm', 'prfruntime', 'pcseguidance', 'dtguidance', 'prfstate', 'genrenm']
        .map((tag) => [tag, field(body, tag)]));
      return { ...item, detail };
    } catch { return null; }
  }));
  const events = [];
  for (const item of details) {
    if (!item?.detail.prfnm || !item.detail.fcltynm || item.detail.prfstate === '공연완료') continue;
    const showing = nextShowing(item.detail, currentTime);
    if (!showing) continue;
    try {
      events.push(validateSavedEvent({
        title: item.detail.prfnm, category: item.genre.category, format: '공연',
        domains: family === '음악' ? ['음악', '문화'] : ['공연', '문화'],
        tags: [item.genre.tag || item.genre.category, '공연'],
        venue: item.detail.fcltynm, ...showing,
        participationFee: item.detail.pcseguidance,
        description: `공연예술통합전산망(KOPIS) 정보로 고른 가장 가까운 공연 회차입니다. 공연 기간 ${item.detail.prfpdfrom}~${item.detail.prfpdto}. 예매 전 공식 안내를 확인해 주세요.`,
        sourceUrl: detailPage(item.id),
      }));
    } catch { /* Skip incomplete official listings. */ }
    if (events.length >= 8) break;
  }
  return events;
}
