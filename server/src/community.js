const text = (value, max) => typeof value === 'string' ? value.trim().slice(0, max) : '';
const coordinate = (value, min, max) => value !== null && value !== '' && value !== undefined &&
  Number.isFinite(Number(value)) && Number(value) >= min && Number(value) <= max
  ? Number(value) : null;

export function communityContext(body = {}) {
  return {
    school: text(body.school, 80), region: text(body.region, 80),
    ageBand: ['under20', '20s', '30s', '40plus'].includes(body.ageBand) ? body.ageBand : '',
    regionLatitude: coordinate(body.regionLatitude, -90, 90),
    regionLongitude: coordinate(body.regionLongitude, -180, 180),
  };
}

export function distanceKm(a, b) {
  if (![a?.latitude, a?.longitude, b?.latitude, b?.longitude].every(Number.isFinite)) return null;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude), dLon = radians(b.longitude - a.longitude);
  const value = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

export function communityMatch(event, context = {}) {
  const same = (key) => Boolean(context[key] && event.community?.[key] === context[key]);
  const school = same('school'), region = same('region'), age = same('ageBand');
  const distance = distanceKm(
    { latitude: context.regionLatitude, longitude: context.regionLongitude },
    { latitude: event.locationLatitude, longitude: event.locationLongitude },
  );
  const nearby = distance != null && distance <= 30;
  const proximityScore = distance == null ? 0 : distance <= 5 ? 7 : distance <= 15 ? 5 : distance <= 30 ? 2 : 0;
  return { score: (school ? 8 : 0) + (region ? 5 : 0) + (age ? 2 : 0) + proximityScore,
    reason: school ? '같은 학교에서 공유된 행사예요.'
      : nearby && age ? `내 활동 지역에서 약 ${Math.max(1, Math.round(distance))}km · 같은 연령대가 공유했어요.`
      : nearby ? `내 활동 지역에서 약 ${Math.max(1, Math.round(distance))}km 떨어진 행사예요.`
      : region ? '같은 활동 지역에서 공유된 행사예요.'
      : age ? '같은 연령대의 사용자가 공유한 행사예요.' : '' };
}

export function eventOrigin(row) {
  if (['shared', 'web', 'demo'].includes(row.origin_kind)) return row.origin_kind;
  if ((typeof row.tags === 'string' ? JSON.parse(row.tags || '[]') : row.tags || []).includes('시연용')) return 'demo';
  if (row.origin_kind === 'catalog') return 'catalog';
  return row.source_url ? 'web' : 'catalog';
}
