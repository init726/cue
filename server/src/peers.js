// "비슷한 사람들이 저장한 행사": 공개 카탈로그 행사를 일정에 넣거나(saved·planned·completed) 관심 표시한
// 사람 수를 센다. 누가 저장했는지는 내보내지 않고, PEER_MIN_SAVERS명(기본 2명) 이상일 때만 보여준다.
// 사용자가 직접 스캔한 개인 일정은 세지 않는다.
import { distanceKm } from './community.js';

const statuses = ['saved', 'planned', 'completed', 'interested'];
const cacheMs = 10 * 60 * 1000;
let cache = null;

export const minSavers = () => Math.max(1, Number(process.env.PEER_MIN_SAVERS) || 2);

const context = (row = {}) => ({
  school: row.school || '', ageBand: row.age_band ?? row.ageBand ?? '',
  regionLatitude: row.region_latitude ?? row.regionLatitude ?? null,
  regionLongitude: row.region_longitude ?? row.regionLongitude ?? null,
  favoriteTopics: Array.isArray(row.favorite_topics) ? row.favorite_topics
    : Array.isArray(row.favoriteTopics) ? row.favoriteTopics : [],
});

const hasContext = (value) => Boolean(value.school || value.ageBand || value.regionLatitude != null || value.favoriteTopics.length);

// 같은 학교, 같은 연령대, 활동 지역 30km 안, 겹치는 관심 분야 중 하나라도 맞으면 비슷한 사람으로 본다.
export function similarPeople(viewer, other) {
  if (!other) return false;
  if (viewer.school && viewer.school === other.school) return true;
  if (viewer.ageBand && viewer.ageBand === other.ageBand) return true;
  const km = distanceKm({ latitude: viewer.regionLatitude, longitude: viewer.regionLongitude },
    { latitude: other.regionLatitude, longitude: other.regionLongitude });
  if (km != null && km <= 30) return true;
  return viewer.favoriteTopics.some((topic) => other.favoriteTopics.includes(topic));
}

// links: [{ userId, eventId }], profiles: Map(userId → 프로필 행). 반환: Map(eventId → { count, similar }).
// 내 환경 정보가 하나도 없으면 비슷함을 따질 수 없으니 전체 사용자 수로 센다.
export function peerCounts({ links, profiles, viewerId, viewer, minimum = minSavers() }) {
  const me = context(viewer);
  const judge = hasContext(me);
  const users = new Map();
  for (const { userId, eventId } of links) {
    if (userId === viewerId) continue;
    if (!users.has(eventId)) users.set(eventId, new Set());
    users.get(eventId).add(userId);
  }
  const counts = new Map();
  for (const [eventId, savers] of users) {
    const count = judge ? [...savers].filter((userId) => similarPeople(me, context(profiles.get(userId)))).length : savers.size;
    if (count >= minimum) counts.set(eventId, { count, similar: judge });
  }
  return counts;
}

// Supabase: 서버 키로 다가오는 카탈로그 행사의 저장 기록과 그 사용자들의 프로필을 읽는다. 10분 동안 재사용한다.
export async function cloudPeerData({ fetchImpl = fetch, currentTime = Date.now() } = {}) {
  if (cache && currentTime - cache.at < cacheMs) return cache.data;
  const url = process.env.SUPABASE_URL?.replace(/\/$/, ''), key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { links: [], profiles: new Map() };
  const get = async (path) => {
    const response = await fetchImpl(`${url}/rest/v1/${path}`, {
      headers: { apikey: key, authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error(`peer data ${response.status}`);
    return response.json();
  };
  const now = new Date(currentTime).toISOString();
  const rows = await get(`user_events?select=user_id,event_id,events!inner(source_type,end_at)` +
    `&status=in.(${statuses.join(',')})&events.source_type=eq.catalog&events.end_at=gt.${now}&limit=5000`);
  const links = rows.map((row) => ({ userId: row.user_id, eventId: row.event_id }));
  const ids = [...new Set(links.map((link) => link.userId))];
  const profiles = new Map();
  for (let index = 0; index < ids.length; index += 100) {
    for (const row of await get(`profiles?select=*&user_id=in.(${ids.slice(index, index + 100).join(',')})`)) {
      profiles.set(row.user_id, row);
    }
  }
  const data = { links, profiles };
  cache = { at: currentTime, data };
  return data;
}

export const peerStatuses = statuses;
