// 카카오 로컬 키워드 검색으로 행사장을 실제 장소(이름·도로명 주소·좌표)에 연결한다.
// 키는 서버 환경 변수에만 두고 앱에는 내려보내지 않는다.
const endpoint = 'https://dapi.kakao.com/v2/local/search/keyword.json';

// 대시보드에 붙여넣을 때 따라 들어오는 따옴표·공백·"KakaoAK " 접두어는 걷어낸다.
const kakaoKey = () => String(process.env.KAKAO_REST_API_KEY || '')
  .trim().replace(/^["']|["']$/g, '').replace(/^KakaoAK\s+/i, '').trim();

export const placesEnabled = () => Boolean(kakaoKey());

export const placeMapUrl = (provider, id) =>
  provider === 'kakao' && /^\d{1,20}$/.test(String(id || '')) ? `https://place.map.kakao.com/${id}` : null;

export async function searchPlaces(query, { latitude, longitude, fetchImpl = fetch } = {}) {
  const text = String(query || '').trim().slice(0, 100);
  if (text.length < 2 || !placesEnabled()) return [];
  const url = new URL(endpoint);
  url.searchParams.set('query', text);
  url.searchParams.set('size', '10');
  // 활동 지역 좌표가 있으면 거리를 함께 받아 가까운 후보를 알아보기 쉽게 한다. 정렬은 정확도 순을 유지한다.
  if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
    url.searchParams.set('y', String(latitude));
    url.searchParams.set('x', String(longitude));
  }
  const response = await fetchImpl(url, {
    headers: { authorization: `KakaoAK ${kakaoKey()}` },
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) {
    console.error('Kakao local status:', response.status);
    throw Object.assign(new Error('장소를 찾지 못했어요. 잠시 후 다시 시도해 주세요.'), { status: 502 });
  }
  const body = await response.json();
  return (Array.isArray(body.documents) ? body.documents : []).flatMap((doc) => {
    const lat = Number(doc.y), lng = Number(doc.x);
    const id = String(doc.id || '');
    if (!/^\d{1,20}$/.test(id) || !doc.place_name || !Number.isFinite(lat) || !Number.isFinite(lng)) return [];
    const distance = Number(doc.distance);
    return [{
      provider: 'kakao', id, name: String(doc.place_name).slice(0, 160),
      address: String(doc.road_address_name || doc.address_name || '').slice(0, 200),
      category: String(doc.category_name || '').split('>').pop().trim().slice(0, 60),
      latitude: lat, longitude: lng,
      distanceMeters: doc.distance === '' || !Number.isFinite(distance) ? null : distance,
      mapUrl: placeMapUrl('kakao', id),
    }];
  });
}
