const text = (value, max) => typeof value === 'string' ? value.trim().slice(0, max) : '';

export function communityContext(body = {}) {
  return {
    school: text(body.school, 80), region: text(body.region, 80),
    ageBand: ['under20', '20s', '30s', '40plus'].includes(body.ageBand) ? body.ageBand : '',
  };
}

export function communityMatch(event, context = {}) {
  const same = (key) => Boolean(context[key] && event.community?.[key] === context[key]);
  const school = same('school'), region = same('region'), age = same('ageBand');
  return { score: (school ? 8 : 0) + (region ? 5 : 0) + (age ? 2 : 0),
    reason: school ? '같은 학교에서 공유된 행사예요.' : region ? '같은 활동 지역에서 공유된 행사예요.'
      : age ? '같은 연령대의 사용자가 공유한 행사예요.' : '' };
}

export function eventOrigin(row) {
  if (['shared', 'web', 'demo'].includes(row.origin_kind)) return row.origin_kind;
  if ((typeof row.tags === 'string' ? JSON.parse(row.tags || '[]') : row.tags || []).includes('시연용')) return 'demo';
  if (row.origin_kind === 'catalog') return 'catalog';
  return row.source_url ? 'web' : 'catalog';
}
