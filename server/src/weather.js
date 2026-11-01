// 행사 장소·시간의 날씨를 Open-Meteo(키 없음, 최대 16일 예보)에서 가져온다.
// 같은 동네(약 1km)·같은 시간 요청은 30분 동안 다시 묻지 않는다.
const endpoint = 'https://api.open-meteo.com/v1/forecast';
const cache = new Map();
const ttlMs = 30 * 60 * 1000;
const hour = 3600000;

// WMO 날씨 코드를 한국어 이름과 앱 아이콘 이름으로 바꾼다.
export function weatherLabel(code) {
  if (code === 0) return { label: '맑음', icon: 'clear' };
  if (code === 1 || code === 2) return { label: '구름 조금', icon: 'partly' };
  if (code === 3) return { label: '흐림', icon: 'cloudy' };
  if (code === 45 || code === 48) return { label: '안개', icon: 'fog' };
  if (code >= 51 && code <= 57) return { label: '이슬비', icon: 'rain' };
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return { label: '비', icon: 'rain' };
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return { label: '눈', icon: 'snow' };
  if (code >= 95) return { label: '뇌우', icon: 'storm' };
  return { label: '날씨 정보', icon: 'cloudy' };
}

const round = (value) => Math.round(value * 100) / 100;

async function forecast(latitude, longitude, fetchImpl) {
  const key = `${round(latitude)},${round(longitude)}`;
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < ttlMs) return cached.body;
  const url = new URL(endpoint);
  url.searchParams.set('latitude', String(round(latitude)));
  url.searchParams.set('longitude', String(round(longitude)));
  url.searchParams.set('hourly', 'temperature_2m,precipitation_probability,weather_code');
  url.searchParams.set('current', 'temperature_2m,weather_code');
  url.searchParams.set('timezone', 'UTC');
  url.searchParams.set('timeformat', 'unixtime');
  url.searchParams.set('forecast_days', '16');
  const response = await fetchImpl(url, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) {
    console.error('Open-Meteo status:', response.status);
    throw Object.assign(new Error('날씨를 불러오지 못했어요.'), { status: 502 });
  }
  const body = await response.json();
  if (cache.size > 500) cache.clear();
  cache.set(key, { at: Date.now(), body });
  return body;
}

// at이 있으면 그 시각에 가장 가까운 시간별 예보를, 없으면 지금 날씨를 돌려준다.
// 예보 범위(약 16일)를 벗어나면 available:false다.
export async function weatherAt(latitude, longitude, at = null, { fetchImpl = fetch } = {}) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return { available: false };
  const body = await forecast(latitude, longitude, fetchImpl);
  if (at == null) {
    const current = body.current || {};
    if (!Number.isFinite(current.temperature_2m)) return { available: false };
    return { available: true, time: new Date(current.time * 1000).toISOString(),
      temperature: Math.round(current.temperature_2m), precipitationProbability: null,
      ...weatherLabel(current.weather_code) };
  }
  const target = Date.parse(at);
  const times = body.hourly?.time || [];
  let best = -1;
  for (let index = 0; index < times.length; index += 1) {
    if (best < 0 || Math.abs(times[index] * 1000 - target) < Math.abs(times[best] * 1000 - target)) best = index;
  }
  if (best < 0 || Math.abs(times[best] * 1000 - target) > hour) return { available: false };
  return { available: true, time: new Date(times[best] * 1000).toISOString(),
    temperature: Math.round(body.hourly.temperature_2m[best]),
    precipitationProbability: body.hourly.precipitation_probability?.[best] ?? null,
    ...weatherLabel(body.hourly.weather_code[best]) };
}
