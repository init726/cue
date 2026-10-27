import { categories, categoryGroup } from './categories.js';
import { validateSavedEvent } from './domain.js';
import { formats, domains } from './classification.js';
import { discoverSemaExhibitions } from './sema.js';
import { discoverKopisPerformances } from './kopis.js';

const maxDiscoveryAge = 180 * 86400000;
const officialDomains = {
  // 서울시립미술관은 sema.js가 공식 페이지를 직접 읽으므로 웹 검색에서는 다른 기관만 찾는다.
  전시: ['mmca.go.kr', 'culture.seoul.go.kr'],
  음악: ['kopis.or.kr', 'sac.or.kr', 'sejongpac.or.kr', 'culture.seoul.go.kr'],
  공연: ['kopis.or.kr', 'sac.or.kr', 'sejongpac.or.kr', 'culture.seoul.go.kr'],
};
const normalizeUrl = (value) => {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:') return null;
    url.hash = '';
    for (const key of [...url.searchParams.keys()]) {
      if (/^(utm_|fbclid|gclid)/i.test(key)) url.searchParams.delete(key);
    }
    return url.toString();
  } catch { return null; }
};

// www.mmca.go.kr처럼 공식 도메인의 하위 도메인도 같은 기관으로 본다.
const isWithin = (value, domain) => {
  const host = new URL(value).hostname;
  return host === domain || host.endsWith(`.${domain}`);
};

const topicsByDomain = { AI: ['기술'], 소프트웨어: ['기술'], 로봇: ['기술'], 과학: ['기술'], 창업: ['기술'],
  정책: ['교육'], 교육: ['교육'], 미술: ['미술 전시'], 디자인: ['전시'], 음악: ['음악'], 공연: ['공연'],
  음식: ['커피·와인', '푸드 페스티벌'], 문화: ['전시', '공연'] };

// 관심 상위 세 분야를 검색 주제로 바꾼다. 같은 주제로 묶이는 분야는 subject에 함께 담는다.
export function discoveryTopics(interests) {
  const topics = [];
  const ranked = [...interests.entries()]
    .filter(([key, score]) => score > 0 && key.startsWith('domain:') && domains.includes(key.slice(7)) && key !== 'domain:기타')
    .sort((a, b) => b[1] - a[1]).slice(0, 3).map(([key]) => key.slice(7));
  for (const domain of ranked) {
    for (const topic of topicsByDomain[domain] || []) {
      if (!categories.includes(topic)) continue;
      const found = topics.find((item) => item.topic === topic);
      if (found) found.domains.push(domain);
      else topics.push({ topic, domains: [domain] });
    }
  }
  return topics.map(({ topic, domains: matched }) => ({ topic, subject: matched.join('·') }));
}

export function discoveryTopic(interests) {
  return discoveryTopics(interests)[0]?.topic || null;
}

export function verifiedDiscoveries(response, currentTime = Date.now()) {
  if (response.status !== 'completed') return [];
  const output = response.output || [];
  const sources = new Set(output.filter((item) => item.type === 'web_search_call')
    .flatMap((item) => item.action?.sources || [])
    .map((item) => normalizeUrl(item.url)).filter(Boolean));
  if (!sources.size) return [];
  const text = output.flatMap((item) => item.content || [])
    .find((item) => item.type === 'output_text')?.text;
  let items;
  try { items = JSON.parse(text).events; } catch { return []; }
  if (!Array.isArray(items)) return [];
  const seen = new Set();
  return items.flatMap((item) => {
    const sourceUrl = normalizeUrl(item.sourceUrl);
    const start = Date.parse(item.startsAt);
    const end = Date.parse(item.endsAt);
    if (!sourceUrl || !sources.has(sourceUrl) || seen.has(sourceUrl) ||
        !categories.includes(item.category) || !Number.isFinite(start) ||
        !Number.isFinite(end) || start <= currentTime ||
        start > currentTime + maxDiscoveryAge || end <= start ||
        !String(item.title || '').trim() || !String(item.venue || '').trim()) return [];
    try {
      const event = validateSavedEvent({ ...item, sourceUrl });
      seen.add(sourceUrl);
      return [event];
    } catch { return []; }
  }).slice(0, 5);
}

export async function discoverEvents(topic, { fetchImpl = fetch, currentTime = Date.now(), subject = topic } = {}) {
  if (!categories.includes(topic) || topic === '기타') return [];
  const family = categoryGroup(topic);
  const schema = {
    type: 'object', additionalProperties: false,
    properties: { events: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        title: { type: 'string' }, category: { type: 'string', enum: categories },
        format: { type: 'string', enum: formats }, domains: { type: 'array', items: { type: 'string', enum: domains } },
        tags: { type: 'array', items: { type: 'string' } },
        startsAt: { type: 'string' }, endsAt: { type: 'string' },
        venue: { type: 'string' }, description: { type: 'string' },
        sourceUrl: { type: 'string' },
      },
      required: ['title', 'category', 'format', 'domains', 'tags', 'startsAt', 'endsAt', 'venue', 'description', 'sourceUrl'],
    } } }, required: ['events'],
  };
  const response = await fetchImpl('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || 'gpt-4.1-mini', store: false,
      tools: [{ type: 'web_search', search_context_size: 'medium' }],
      tool_choice: 'required', include: ['web_search_call.action.sources'],
      input: `현재 ${new Date(currentTime).toISOString()}. 한국에서 앞으로 180일 안에 열리는 실제 ${subject} 및 관련 과학·소프트웨어·교육·정책 주제의 ${topic} (${family}) 행사를 최대 5개 찾으세요. ${officialDomains[family] ? `site:${officialDomains[family].join(' 또는 site:')} 사이트에서만 찾으세요.` : ''} 각 행사에 대해 주최자·공공기관·공식 행사장의 개별 상세 페이지에서 제목, 날짜와 시간, 장소를 확인하세요. 검색 결과 목록·검색 페이지·홈페이지 주소는 제외하세요. 페이지에 근거가 없으면 반환하지 마세요. sourceUrl은 검색한 공식 상세 페이지 URL 그대로여야 합니다. startsAt과 endsAt은 +09:00을 포함한 ISO 8601로 쓰세요. 진행 중인 전시처럼 기간과 관람 시간이 따로 있다면 내일 이후 실제 관람 가능한 날의 방문 시간 14:00~16:00을 추천하고 후보마다 서로 다른 방문 날짜를 택하세요. description에 '추천 방문 시간'임을 밝히세요. 이미 지난 일정이나 운영 시간이 불명확한 행사는 제외하세요. 결과는 한국어로 작성하고 관련된 세부 카테고리를 고르세요. format에는 행사 형식, domains에는 제목과 상세 내용으로 확인한 실제 주제 분야만 넣으세요. 찾지 못하면 events를 빈 배열로 반환하세요.`,
      text: { format: { type: 'json_schema', name: 'event_discovery', strict: true, schema } },
    }),
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) {
    console.error('OpenAI discovery status:', response.status);
    throw new Error('행사 검색에 실패했어요.');
  }
  return verifiedDiscoveries(await response.json(), currentTime)
    .filter((event) => categoryGroup(event.category) === family &&
      (!officialDomains[family] || officialDomains[family].some((domain) => isWithin(event.sourceUrl, domain))));
}

// 분야별로 공식 출처를 먼저 쓰고, 부족할 때만 웹 검색을 쓴다.
export async function discoverCatalogEvents(topic, { subject = topic, fetchImpl = fetch, currentTime = Date.now() } = {}) {
  const family = categoryGroup(topic);
  const sources = [];
  if (family === '전시') {
    sources.push(discoverSemaExhibitions({ fetchImpl, currentTime }), discoverEvents(topic, { fetchImpl, currentTime, subject }));
  } else if (process.env.KOPIS_API_KEY && ['음악', '공연'].includes(family)) {
    try {
      const performances = await discoverKopisPerformances(family, { fetchImpl, currentTime });
      if (performances.length) return performances;
    } catch (error) {
      console.error('KOPIS discovery:', error instanceof Error ? error.message : error);
    }
    sources.push(discoverEvents(topic, { fetchImpl, currentTime, subject }));
  } else {
    sources.push(discoverEvents(topic, { fetchImpl, currentTime, subject }));
  }
  const results = await Promise.allSettled(sources);
  const found = results.filter((result) => result.status === 'fulfilled').flatMap((result) => result.value);
  if (!found.length && results.every((result) => result.status === 'rejected')) throw results[0].reason;
  const urls = new Set();
  return found.filter((event) => !urls.has(event.sourceUrl) && urls.add(event.sourceUrl));
}
