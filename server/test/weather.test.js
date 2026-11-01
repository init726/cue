import test from 'node:test';
import assert from 'node:assert/strict';
import { weatherAt, weatherLabel } from '../src/weather.js';

test('the hourly forecast nearest the event start is returned and the area is cached', async () => {
  let calls = 0, asked;
  const start = Date.parse('2026-11-14T10:00:00Z') / 1000;
  const fetchImpl = async (url) => {
    calls += 1;
    asked = String(url);
    return new Response(JSON.stringify({
      current: { time: start - 7200, temperature_2m: 9.6, weather_code: 3 },
      hourly: { time: [start - 3600, start, start + 3600], temperature_2m: [12.2, 11.4, 10.1],
        precipitation_probability: [10, 60, 80], weather_code: [1, 61, 63] },
    }));
  };
  const at = await weatherAt(37.56423, 126.97345, '2026-11-14T19:10:00+09:00', { fetchImpl });
  assert.deepEqual(at, { available: true, time: '2026-11-14T10:00:00.000Z', temperature: 11,
    precipitationProbability: 60, label: '비', icon: 'rain' });
  assert.match(asked, /latitude=37.56&longitude=126.97/, '좌표는 약 1km로 줄여 보낸다');
  const now = await weatherAt(37.5649, 126.9711, null, { fetchImpl });
  assert.equal(now.label, '흐림');
  assert.equal(now.temperature, 10);
  assert.equal(calls, 1, '같은 동네는 캐시를 쓴다');
  assert.deepEqual(await weatherAt(37.56, 126.97, '2027-03-01T00:00:00Z', { fetchImpl }), { available: false });
  assert.deepEqual(await weatherAt(Number.NaN, 1, null, { fetchImpl }), { available: false });
});

test('weather codes read as short Korean labels', () => {
  assert.equal(weatherLabel(0).label, '맑음');
  assert.equal(weatherLabel(2).icon, 'partly');
  assert.equal(weatherLabel(73).label, '눈');
  assert.equal(weatherLabel(96).icon, 'storm');
});
