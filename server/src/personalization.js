import { classifyEvent } from './classification.js';
import { communityMatch, distanceKm } from './community.js';

export const personalizationRules = Object.freeze({
  decayDays: 90,
  interestWeights: Object.freeze({ viewed: 0.2, recommendation_opened: 0.3, interested: 2,
    saved: 4, plan_created: 5, completed: 4, not_interested: -3,
    recommendation_dismissed: -2, unsaved: -1 }),
});
const parse = (value, fallback) => { try { return typeof value === 'string' ? JSON.parse(value) : (value ?? fallback); } catch { return fallback; } };
const normalizeTag = (tag) => String(tag).toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
const aliases = { 인공지능: 'ai', 생성형ai: 'ai', 미래교육: '교육', 교육정책: '교육정책', 현대미술: '미술' };
const tagKey = (tag) => aliases[normalizeTag(tag)] || normalizeTag(tag);
const relatedDomains = {
  AI: ['소프트웨어', '로봇', '과학', '교육', '정책'],
  교육: ['AI', '정책', '과학', '소프트웨어'],
  정책: ['교육', 'AI', '과학', '창업'],
  소프트웨어: ['AI', '로봇', '과학', '창업'],
  로봇: ['AI', '소프트웨어', '과학'],
  과학: ['AI', '로봇', '소프트웨어', '교육'],
  미술: ['디자인'], 디자인: ['미술'],
  음악: ['공연'], 공연: ['음악', '영화'], 창업: ['소프트웨어', 'AI', '정책', '커리어'],
  영화: ['공연', '문화'], 책: ['교육', '문화'], 스포츠: ['건강', '여행'], 건강: ['스포츠'],
  게임: ['소프트웨어'], 커리어: ['창업', '교육'], 패션: ['디자인'], 여행: ['스포츠', '환경'],
  환경: ['정책', '과학', '여행'], 역사: ['문화', '교육'], 반려동물: [],
};

// 관심 없음 이유 중 분야와 상관없는 것은 pref: 신호로 남긴다. 순위를 매길 때 거리·비용·시간대 감점으로 쓴다.
const kst = (ms) => new Date(ms + 9 * 3600000);
export function timeBand(startsAt) {
  const time = kst(Date.parse(startsAt));
  if (!Number.isFinite(time.getTime())) return null;
  const day = time.getUTCDay();
  if (day === 0 || day === 6) return 'weekend';
  return time.getUTCHours() >= 18 ? 'weekday_evening' : 'weekday_day';
}
const preferenceKeys = (row, reason) => {
  if (reason === '장소가 멂') return ['pref:far'];
  if (reason === '비쌈') return ['pref:paid'];
  if (reason === '시간 안 맞음') {
    const band = timeBand(row.start_at || row.startsAt);
    return band ? [`pref:band:${band}`] : [];
  }
  return [];
};

export function interestSignals(interactions, currentTime = Date.now()) {
  const scores = new Map();
  for (const row of interactions) {
    const metadata = parse(row.metadata, {});
    const reason = metadata?.reason;
    if (row.action === 'not_interested') {
      const ageDays = Math.max(0, (currentTime - Date.parse(row.created_at)) / 86400000);
      for (const key of preferenceKeys(row, reason)) {
        const entry = scores.get(key) || { score: 0, count: 0 };
        entry.score += Math.exp(-ageDays / personalizationRules.decayDays);
        entry.count += 1;
        scores.set(key, entry);
      }
    }
    const weight = row.action === 'not_interested' && reason && reason !== '관심 없는 분야'
      ? 0 : (personalizationRules.interestWeights[row.action] ?? 0);
    if (!weight) continue;
    const ageDays = Math.max(0, (currentTime - Date.parse(row.created_at)) / 86400000);
    const value = weight * Math.exp(-ageDays / personalizationRules.decayDays);
    const classification = classifyEvent({ ...row, tags: parse(row.tags, []), domains: parse(row.domains, []) });
    for (const [key, strength] of [
      ...classification.domains.filter((domain) => domain !== '기타').map((domain) => [`domain:${domain}`, 1]),
      ...parse(row.tags, []).map((tag) => [`tag:${tagKey(tag)}`, 0.55]),
      [`format:${classification.format}`, 0.12],
    ]) {
      if (!key || key.endsWith(':')) continue;
      const entry = scores.get(key) || { score: 0, count: 0 };
      entry.score += value * strength;
      entry.count += 1;
      scores.set(key, entry);
    }
  }
  return scores;
}

// 시연 모드: 관심사가 없거나 맞는 행사가 적어도 다가오는 행사를 탐색용으로 채워 보여준다.
const exploreMinimum = 6;
const exploreSize = 8;
export const exploreEnabled = () => process.env.CUE_DEMO_MODE === '1';

// 같은 seed와 행사 id면 항상 같은 0~1 값을 돌려주는 가벼운 해시. 새로고침마다 seed를 바꿔 순서를 섞는다.
function seededRandom(seed, id) {
  let h = 2166136261 ^ Number(seed);
  for (const ch of String(id)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  h ^= h >>> 15; h = Math.imul(h, 2246822507); h ^= h >>> 13;
  return ((h >>> 0) % 100000) / 100000;
}
const varietyJitter = 0.4;
const seenPenalty = 0.4;
const peerEventKey = (event) => `${String(event.title || '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')}|${String(event.startsAt || '').slice(0, 10)}`;

// 추천 점수는 신호마다 0~1로 맞춘 뒤 아래 가중치로 더한다. 가중치를 바꿀 때는 이 표만 고친다.
export const rankingWeights = Object.freeze({ interest: 0.5, peer: 0.15, proximity: 0.15, affinity: 0.1, urgency: 0.1 });
const listSize = 12;
// 다른 사용자가 공유한 행사는 '내 주변' 묶음에 이 개수까지 보여준다.
const communitySlots = 5;
// 공유 행사끼리는 거리를 가장 크게 보고, 같은 학교·연령대, 관심사, 여러 명이 공유했는지 순으로 본다.
export const communityWeights = Object.freeze({ proximity: 0.45, affinity: 0.25, interest: 0.2, peer: 0.1 });
// 한 분야가 목록 위쪽을 독차지하지 않게 분야마다 이 개수까지만 먼저 보여준다.
const perTopicCap = 2;
const nearbyKm = 30;
const day = 86400000;
const saturate = (value, scale) => value > 0 ? 1 - Math.exp(-value / scale) : 0;

export function rankingSignals(event, { interestRaw, peerCount, community, distance, currentTime }) {
  const closesAt = Math.min(Date.parse(event.applicationDeadline) || Infinity,
    Date.parse(event.endsAt) - Date.parse(event.startsAt) > day ? Date.parse(event.endsAt) : Infinity);
  const daysLeft = (closesAt - currentTime) / day;
  return {
    interest: saturate(interestRaw, 8),
    peer: peerCount >= 2 ? Math.min(1, Math.log2(peerCount) / 3) : 0,
    proximity: distance == null ? 0 : Math.max(0, 1 - distance / nearbyKm),
    affinity: community.school ? 1 : community.region ? 0.5 : community.age ? 0.4 : 0,
    // 신청 마감이나 기간형 행사 종료가 7일 안으로 다가오면 조금 올린다.
    urgency: Number.isFinite(daysLeft) && daysLeft <= 7 ? Math.max(0, 1 - daysLeft / 7) : 0,
  };
}

const weighted = (signals) => Object.entries(rankingWeights)
  .reduce((sum, [key, weight]) => sum + weight * signals[key], 0);

function spreadTopics(events) {
  const counts = new Map(), head = [], tail = [];
  for (const event of events) {
    const topic = event.domains?.find((domain) => domain !== '기타') || event.category || '기타';
    const count = counts.get(topic) || 0;
    (count < perTopicCap ? head : tail).push(event);
    counts.set(topic, count + 1);
  }
  return [...head, ...tail];
}

const favoriteBoost = 3;
// 온보딩에서 고른 관심 분야는 기록이 없어도 처음부터 관심사로 친다. 관심 없음으로 깎인 점수보다 직접 고른 것을 따른다.
export function withFavorites(interests, favorites = []) {
  const merged = new Map(interests);
  for (const domain of favorites) {
    const key = `domain:${domain}`;
    merged.set(key, Math.max(0, merged.get(key) || 0) + favoriteBoost);
  }
  return merged;
}

const isPaid = (fee) => {
  const text = String(fee || '');
  // "0원"은 금액 전체가 0일 때만 무료다("30,000원"의 끝자리 0원은 유료).
  const free = /무료|free/i.test(text) || /(^|[^\d,])0\s*원/.test(text);
  return Boolean(text) && !free && /\d|원|유료/.test(text);
};

// 관심 없음 이유로 배운 감점. 한 번(최근)이면 거리·비용, 같은 시간대는 두 번부터 적용한다.
export function preferencePenalty(event, interests, distance) {
  let factor = 1;
  if ((interests.get('pref:far') || 0) >= 0.8 && distance != null && distance > 10) factor *= 0.6;
  if ((interests.get('pref:paid') || 0) >= 0.8 && isPaid(event.participationFee)) factor *= 0.7;
  const band = timeBand(event.startsAt);
  if (band && (interests.get(`pref:band:${band}`) || 0) >= 1.6) factor *= 0.7;
  return factor;
}

const fitWindowMs = 7 * 86400000;
const busyBufferMs = 30 * 60000;
const sameDayKm = 2;
const sectionSlots = 3;
const weekdayNames = ['일', '월', '화', '수', '목', '금', '토'];
const kstDate = (ms) => kst(ms).toISOString().slice(0, 10);
const kstClock = (ms) => kst(ms).toISOString().slice(11, 16);

export function rankRecommendations({ catalog, saved, interests: learned, excluded, currentTime = Date.now(), explore = false, seed = null, seen = new Set(), context = {}, userId = null, favorites = [], busy = null }) {
  const interests = withFavorites(learned, favorites);
  // Old profile keys can still be read until the store recomputes them.
  const positiveDomains = [...interests.entries()].filter(([key, score]) => key.startsWith('domain:') && score > 0);
  const specificInterests = positiveDomains.filter(([key]) => !['domain:문화', 'domain:기타'].includes(key));
  const home = { latitude: context.regionLatitude, longitude: context.regionLongitude };
  const peerGroups = new Map();
  for (const event of catalog) {
    if (event.originKind !== 'shared' || event.sharingUserId === userId || communityMatch(event, context).score <= 0) continue;
    const key = peerEventKey(event), owners = peerGroups.get(key) || new Set();
    if (event.sharingUserId) owners.add(event.sharingUserId);
    peerGroups.set(key, owners);
  }
  const ranked = catalog
    .filter((event) => (!userId || event.sharingUserId !== userId) && Date.parse(event.endsAt) > currentTime &&
      (!event.applicationDeadline || Date.parse(event.applicationDeadline) > currentTime) &&
      !excluded.has(event.id) && !saved.some((own) => own.title === event.title) &&
      !saved.some((own) => Date.parse(own.startsAt) < Date.parse(event.endsAt) &&
        Date.parse(event.startsAt) < Date.parse(own.endsAt)))
    .map((event) => {
      const classification = classifyEvent(event);
      const community = event.originKind === 'shared' ? communityMatch(event, context) : { score: 0, reason: '' };
      const peerCount = peerGroups.get(peerEventKey(event))?.size || 0;
      const matchedDomains = classification.domains.filter((domain) => (interests.get(`domain:${domain}`) || 0) > 0 && domain !== '기타');
      const domainScore = matchedDomains.reduce((sum, domain) => sum + interests.get(`domain:${domain}`), 0);
      const relatedScore = [...interests.entries()].filter(([key, value]) => key.startsWith('domain:') && value > 0 &&
        relatedDomains[key.slice(7)]?.some((domain) => classification.domains.includes(domain)))
        .reduce((sum, [, value]) => sum + value, 0);
      const tagScore = (event.tags || []).reduce((sum, tag) => sum + Math.max(0, interests.get(`tag:${tagKey(tag)}`) || 0), 0);
      // A matching format alone must never recommend an unrelated topic.
      const eligible = positiveDomains.length > 0 && (matchedDomains.length > 0 || relatedScore > 0) &&
        (!specificInterests.length || matchedDomains.some((domain) => domain !== '문화') || relatedScore > 0);
      const formatScore = Math.max(0, interests.get(`format:${classification.format}`) || 0);
      const interestRaw = eligible ? domainScore * 4 + relatedScore * 0.6 + tagScore * 1.5 + formatScore * 0.2 : 0;
      const distance = distanceKm(home, { latitude: event.locationLatitude, longitude: event.locationLongitude });
      const signals = rankingSignals(event, { interestRaw, peerCount, community, distance, currentTime });
      // 환경이 맞는 사람이 공유한 행사는 관심사와 상관없이 '내 주변' 후보가 된다.
      const discovery = event.originKind === 'shared' && community.score > 0;
      const base = discovery
        ? Object.entries(communityWeights).reduce((sum, [key, weight]) => sum + weight * signals[key], 0)
        : signals.interest ? weighted(signals) : 0;
      const score = base * preferencePenalty(event, interests, distance);
      const reason = peerCount >= 2 ? `비슷한 환경의 사용자 ${peerCount}명이 공유한 행사예요.` : community.reason || (matchedDomains.length ? `${matchedDomains.slice(0, 2).join('·')} 주제에 보인 관심을 바탕으로 추천해요.` :
        relatedScore > 0 ? '관심 주제와 가까운 분야의 행사예요.' : '');
      return { ...event, ...classification, score, reason, discovery, distance, ...(peerCount >= 2 ? { peerCount } : {}) };
    })
    .sort((a, b) => b.score - a.score || Date.parse(a.startsAt) - Date.parse(b.startsAt));
  // seed가 있으면 점수를 조금 흔들고 방금 본 행사는 뒤로 미뤄 새로고침마다 다른 행사가 섞여 나오게 한다.
  const varied = (event, base) => seed == null ? base
    : base * (1 + varietyJitter * (seededRandom(seed, event.id) * 2 - 1)) * (seen.has(event.id) ? seenPenalty : 1);
  const byVariety = (list) => seed == null ? list
    : [...list].sort((a, b) => varied(b, b.score) - varied(a, a.score));
  const unique = (events) => {
    const keys = new Set();
    return events.filter((event) => {
      const key = event.originKind === 'shared' ? peerEventKey(event) : event.id;
      if (keys.has(key)) return false;
      keys.add(key);
      return true;
    });
  };
  // section은 추천 탭의 묶음이다. fits: 이번 주 비어 있는 시간, sameDay: 저장한 일정 근처,
  // nearby: 가까운 사람들이 공유, interest: 관심 주제와 맞음, explore: 둘러보기.
  const strip = ({ discovery, distance, ...event }, section) => ({ ...event, section });
  // 공유 행사는 환경이 맞는 경우(nearby 후보)만 다른 묶음에도 넣을 수 있다.
  const openToAll = (event) => event.originKind !== 'shared' || event.discovery;
  const byRelevance = (a, b) => (b.score > 0) - (a.score > 0) || b.score - a.score || Date.parse(a.startsAt) - Date.parse(b.startsAt);
  const picked = new Set();
  const take = (events) => events.filter((event) => !picked.has(event.id) && picked.add(event.id));

  // 저장한 일정과 같은 날, 2km 안에서 시간이 겹치지 않는 행사.
  const anchors = saved.filter((own) => Number.isFinite(own.locationLatitude) && Date.parse(own.endsAt) > currentTime);
  const sameDay = take(unique(ranked.filter(openToAll).flatMap((event) => {
    const start = Date.parse(event.startsAt);
    const anchor = anchors.map((own) => ({ own, km: distanceKm(
      { latitude: own.locationLatitude, longitude: own.locationLongitude },
      { latitude: event.locationLatitude, longitude: event.locationLongitude }) }))
      .filter(({ own, km }) => km != null && km <= sameDayKm && kstDate(Date.parse(own.startsAt)) === kstDate(start))
      .sort((a, b) => a.km - b.km)[0];
    if (!anchor) return [];
    const meters = Math.max(100, Math.round(anchor.km * 10) * 100);
    return [{ ...event, reason: `${anchor.own.title} 일정 근처 약 ${meters >= 1000 ? `${(meters / 1000).toFixed(1)}km` : `${meters}m`}`, near: anchor.km }];
  }).sort((a, b) => byRelevance(a, b) || a.near - b.near)).slice(0, sectionSlots))
    .map(({ near, ...event }) => strip(event, 'sameDay'));

  // 앞으로 7일 안에 시작하고 캘린더의 바쁜 시간과 30분 이상 떨어진 행사. 주말을 먼저 보여준다.
  const free = (event) => !busy.some((slot) => Date.parse(event.startsAt) < slot.end + busyBufferMs &&
    Date.parse(event.endsAt) > slot.start - busyBufferMs);
  const weekend = (event) => [0, 6].includes(kst(Date.parse(event.startsAt)).getUTCDay());
  const fits = !busy ? [] : take(unique(ranked.filter((event) => openToAll(event) &&
    Date.parse(event.startsAt) > currentTime + 2 * 3600000 && Date.parse(event.startsAt) <= currentTime + fitWindowMs && free(event))
    .sort((a, b) => (b.score > 0) - (a.score > 0) || weekend(b) - weekend(a) || byRelevance(a, b))).slice(0, sectionSlots))
    .map((event) => {
      const start = Date.parse(event.startsAt);
      return strip({ ...event, reason: `${weekdayNames[kst(start).getUTCDay()]}요일 ${kstClock(start)}에 캘린더가 비어 있어요.` }, 'fits');
    });
  const planned = [...fits, ...sameDay];
  const rest = ranked.filter((event) => !picked.has(event.id));
  const relevant = spreadTopics(unique(byVariety(rest.filter((event) => event.score > 0 && !event.discovery))));
  const discovered = unique(byVariety(rest.filter((event) => event.score > 0 && event.discovery))).slice(0, communitySlots);
  const matched = [...relevant.slice(0, listSize - discovered.length).map((event) => strip(event, 'interest')),
    ...discovered.map((event) => strip(event, 'nearby'))];
  if (!explore || matched.length >= exploreMinimum) return [...planned, ...matched];
  // 맞는 행사가 적으면 다가오는 행사를 가까운 순서로 채워 탭이 비지 않게 한다.
  // 사용자가 공유한 행사는 같은 학교·지역·연령대에게만 보여야 하므로 둘러보기에 넣지 않는다.
  const reason = positiveDomains.length ? '새로운 관심사를 발견할 수 있는 행사예요.' : '다가오는 행사예요. 저장할수록 취향에 맞춰 추천해요.';
  const nearFirst = rest.filter((event) => event.score <= 0 && event.originKind !== 'shared')
    .sort((a, b) => (a.distance ?? Infinity) - (b.distance ?? Infinity) || Date.parse(a.startsAt) - Date.parse(b.startsAt));
  // 가까운 순서를 기본 점수로 두고 새로고침 seed로 섞는다.
  const filler = unique(byVariety(nearFirst.map((event, index) => ({ ...event, score: 1 - index / (nearFirst.length + 1) }))))
    .map((event) => strip({ ...event, score: 0.01, reason }, 'explore'));
  return [...planned, ...[...matched, ...filler].slice(0, Math.max(exploreSize, matched.length))];
}

export function memoryFromSignal(key, value) {
  if (key.startsWith('pref:') || value.count < 2 || Math.abs(value.score) < 2) return null;
  const positive = value.score > 0;
  const label = key.replace(/^(domain|tag|format):/, '');
  return { memoryType: positive ? 'interest' : 'avoidance',
    content: positive ? `${label} 주제에 반복적으로 관심을 보였습니다.` : `${label} 주제에 반복적으로 관심 없음을 표시했습니다.`,
    confidence: Math.min(0.95, 0.2 + value.count * 0.15) };
}
