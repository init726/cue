export const formats = Object.freeze(['토론회', '강연', '세미나', '전시', '공연', '해커톤', '공모전', '체험', '기타']);
export const domains = Object.freeze(['AI', '교육', '정책', '소프트웨어', '로봇', '과학', '미술', '음악', '공연', '음식', '디자인', '문화', '창업', '기타']);

const clues = {
  AI: /\bAI\b|인공지능|머신러닝|생성형/i,
  교육: /교육|학교|학습|교사|학생|미래교육/,
  정책: /정책|제도|법안|공공|국정|규제/,
  소프트웨어: /소프트웨어|SW|개발자|코딩|프로그래밍|클라우드/i,
  로봇: /로봇|로보틱스/,
  과학: /과학|연구|물리|생명공학/,
  미술: /미술|개인전|작가|회화|조각|현대미술|갤러리/,
  음악: /음악|콘서트|클래식|재즈|오케스트라/,
  공연: /공연|연극|뮤지컬|무용|발레|오페라|국악|마술/,
  음식: /커피|카페|바리스타|와인|맥주|푸드|음식|요리|미식|디저트|베이커리/,
  디자인: /디자인|시각예술|그래픽/,
  문화: /문화|예술|전시|공연/,
  창업: /창업|스타트업|벤처/,
};
const titleCategories = [
  [/커피|카페|바리스타|와인/, '커피·와인', ['음식']],
  [/푸드|음식|요리|미식|디저트|베이커리/, '푸드 페스티벌', ['음식']],
  [/뮤지컬/, '뮤지컬', ['공연']], [/연극/, '연극', ['공연']],
  [/클래식/, '클래식', ['음악']], [/재즈/, '재즈', ['음악']],
  [/콘서트/, '콘서트', ['음악']], [/개인전|미술/, '미술 전시', ['미술', '문화']],
  [/사진전|사진\s*전시/, '사진 전시', ['미술', '문화']],
  [/해커톤|코딩|소프트웨어|\bAI\b|인공지능/i, '기술', null],
];
const formatClues = {
  토론회: /토론회|포럼|심포지엄/, 강연: /강연|특강|강의/, 세미나: /세미나|컨퍼런스|학회/,
  전시: /전시|개인전|기획전/, 공연: /공연|콘서트|연극|뮤지컬/, 해커톤: /해커톤/,
  공모전: /공모전|경진대회/, 체험: /체험|워크숍/,
};

export function classifyEvent(event) {
  const title = String(event.title || '');
  const text = [title, event.description, ...(event.tags || [])].join(' ');
  const strong = titleCategories.find(([pattern]) => pattern.test(title));
  const titleDomains = strong?.[2] || domains.filter((domain) => domain !== '기타' && clues[domain]?.test(title));
  const inferred = domains.filter((domain) => domain !== '기타' && clues[domain]?.test(text));
  // Legacy categories may describe the event's form, so use them only if content gives no clue.
  if (!inferred.length && ['교육', '음악', '미술', '디자인'].includes(event.category)) inferred.push(event.category);
  if (!inferred.length && /미술 전시|사진 전시/.test(event.category || '')) inferred.push('미술', '문화');
  if (!inferred.length && ['공연', '뮤지컬', '연극', '무용'].includes(event.category)) inferred.push('공연', '문화');
  const explicit = Array.isArray(event.domains) ? event.domains.filter((value) => domains.includes(value) && value !== '기타') : [];
  // 제목의 구체적인 단어를 AI 태그보다 우선한다. 예: 커피 페스티벌은 부대 공연이 있어도 음식 행사다.
  const selectedDomains = [...new Set(titleDomains.length ? titleDomains : (explicit.length ? explicit : inferred))];
  const inferredFormat = formats.find((format) => format !== '기타' && formatClues[format]?.test(text)) ||
    (formats.includes(event.category) ? event.category : '기타');
  return { category: strong?.[1] || (event.category || '기타'),
    format: formats.includes(event.format) && event.format !== '기타' ? event.format : inferredFormat,
    domains: selectedDomains.length ? selectedDomains : ['기타'] };
}
