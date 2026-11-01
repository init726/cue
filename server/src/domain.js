import { randomUUID } from 'node:crypto';
import { categories } from './categories.js';
import { classifyEvent, titleCategory } from './classification.js';

export { categories } from './categories.js';
const hasTimezone = (value) => /^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d+)?)?(?:Z|[+-]\d\d:\d\d)$/.test(value);
const invalid = (message) => Object.assign(new Error(message), { status: 400 });

// 안내문 날짜 표기가 월·일을 실제로 담고 있는지 본다(예: 11.7(토), 10월 9일, 2026-10-09). "2일간", "추후 공지"는 날짜가 아니다.
const hasCalendarDate = (text) => /(?<!\d)\d{1,2}\s*월\s*\d{1,2}|(?<!\d)\d{1,2}\s*[./-]\s*\d{1,2}(?!\d)|\d{4}\s*[./-]\s*\d{1,2}\s*[./-]\s*\d{1,2}/.test(text);
const hasClockTime = (text) => /(?:오전|오후)\s*\d{1,2}(?::\d{2})?\s*시?|(?<!\d)(?:[01]?\d|2[0-3])\s*:\s*[0-5]\d(?!\d)|(?<!\d)\d{1,2}\s*시(?:\s*\d{1,2}\s*분)?/.test(text);

// "서울 건국대학교, 대전 KT인재개발원"처럼 장소 여러 곳이 한 줄로 합쳐진 항목은 장소마다 후보로 나눈다.
// 층·호수 같은 세부 위치(코엑스, 3층 A홀)는 나누지 않도록 각 조각이 충분히 길고 숫자로 시작하지 않을 때만 쪼갠다.
function splitVenues(session) {
  const parts = session.venue.split(/\s*[,、/]\s*|\s+(?:및|또는|그리고)\s+/).map((part) => part.trim()).filter(Boolean);
  if (parts.length < 2 || parts.length > 6 || parts.some((part) => part.length < 3 || /^\d/.test(part))) return [session];
  return parts.map((venue) => ({ ...session, venue, label: session.label || venue }));
}

// 같은 장소에서 시간이 이어지거나 겹치는 항목은 한 행사의 식순이므로 하나의 세션으로 합친다.
function mergeContiguousSessions(items) {
  const merged = [];
  for (const item of [...items].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt))) {
    const last = merged[merged.length - 1];
    if (last && last.venue === item.venue && Date.parse(item.startsAt) <= Date.parse(last.endsAt)) {
      if (Date.parse(item.endsAt) > Date.parse(last.endsAt)) last.endsAt = item.endsAt;
      last.label = '';
    } else merged.push({ ...item });
  }
  return merged;
}

const isoDate = (value) => {
  const text = String(value || '').trim();
  if (!/^\d{4}-\d\d-\d\d$/.test(text)) return null;
  const date = new Date(`${text}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === text ? text : null;
};
const clock = (value) => {
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(String(value || '').trim());
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
};
const asClock = (minutes) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
const weekdaySet = (value) => [...new Set((Array.isArray(value) ? value : []).map(Number)
  .filter((day) => Number.isInteger(day) && day >= 1 && day <= 7))].sort();

// 기간형 행사는 보통 머무는 시간을 종류별 기본값으로 잡는다. 안내문에 소요 시간이 있으면 그 값을 쓴다.
function defaultVisitMinutes(category, tags) {
  if (tags.some((tag) => tag.includes('팝업'))) return 45;
  if (category === '박람회') return 120;
  if (category.includes('페스티벌')) return 180;
  return 90;
}

// 전시·팝업·박람회처럼 기간 안에 자유롭게 방문하는 행사를 날짜 목록 대신 기간·운영 시간·휴관일로 정리한다.
// 하루짜리이거나 안내문에 날짜가 실제로 적혀 있지 않으면 기간형으로 보지 않는다.
export function cleanPeriod(raw, category = '기타', tags = []) {
  if (!raw || typeof raw !== 'object') return null;
  const startDate = isoDate(raw.start_date), endDate = isoDate(raw.end_date);
  const venue = String(raw.venue || '').trim().slice(0, 160);
  const dateText = String(raw.date_text || '').trim().slice(0, 120);
  if (!startDate || !endDate || endDate <= startDate || !venue || !hasCalendarDate(dateText)) return null;
  const hoursText = String(raw.hours_text || '').trim().slice(0, 160);
  const closedWeekdays = weekdaySet(raw.closed_weekdays);
  // 정기 휴관 요일이 운영 요일에도 들어가 있으면(예: 공휴일 운영 시간에 월요일을 넣은 경우) 휴관을 따른다.
  const hours = !hasClockTime(hoursText) ? [] : (Array.isArray(raw.hours) ? raw.hours : []).slice(0, 7).flatMap((item) => {
    const weekdays = weekdaySet(item?.weekdays).filter((day) => !closedWeekdays.includes(day));
    const open = clock(item?.open), close = clock(item?.close);
    const lastEntry = clock(item?.last_entry);
    if (!weekdays.length || open == null || close == null || close <= open) return [];
    return [{ weekdays, open: asClock(open), close: asClock(close),
      lastEntry: lastEntry != null && lastEntry > open && lastEntry <= close ? asClock(lastEntry) : null }];
  });
  const visit = Number(raw.visit_minutes);
  return {
    startDate, endDate, venue, dateText, hoursText, hours,
    closedWeekdays,
    closedDates: [...new Set((Array.isArray(raw.closed_dates) ? raw.closed_dates : []).map(isoDate)
      .filter((day) => day && day >= startDate && day <= endDate))].sort().slice(0, 60),
    visitMinutes: Number.isInteger(visit) && visit >= 30 && visit <= 480 ? visit : defaultVisitMinutes(category, tags),
  };
}

export function cleanExtraction(raw) {
  if (!raw || raw.is_event !== true) return null;
  const title = String(raw.title || '').trim().slice(0, 120);
  // AI가 붙인 종류는 제목의 구체적인 핵심어로 바로잡는다. 예: 커피 페스티벌은 부대 공연이 있어도 커피·와인.
  const category = titleCategory(title) || (categories.includes(raw.category) ? raw.category : '기타');
  const tags = (Array.isArray(raw.tags) ? raw.tags : []).filter((tag) => typeof tag === 'string')
    .map((tag) => tag.trim().slice(0, 40)).filter(Boolean).slice(0, 8);
  const rawSessions = (Array.isArray(raw.sessions) ? raw.sessions : [])
    .slice(0, 12)
    .map((item) => ({
      label: String(item.label || '').trim().slice(0, 80),
      startsAt: String(item.starts_at || '').trim(),
      endsAt: String(item.ends_at || '').trim(),
      venue: String(item.venue || '').trim().slice(0, 160),
      dateText: typeof item.date_text === 'string' ? item.date_text.trim() : null,
      timeText: typeof item.time_text === 'string' ? item.time_text.trim() : null,
    }))
    // 안내문에 날짜가 적혀 있지 않은데 AI가 채운 일정은 버려 사용자가 직접 고르게 한다.
    .filter((item) => item.dateText === null || hasCalendarDate(item.dateText))
    // 00:00은 안내문에 실제 표기된 자정일 때만 통과한다. 시간 미표기 일정은 사용자에게 다시 묻는다.
    .filter((item) => item.timeText === null || hasClockTime(item.timeText))
    .filter((item) => {
      const start = Date.parse(item.startsAt);
      const end = Date.parse(item.endsAt);
      return hasTimezone(item.startsAt) && hasTimezone(item.endsAt) && Number.isFinite(start) && Number.isFinite(end) && end > start && item.venue;
    });
  const period = cleanPeriod(raw.period, category, tags);
  // 기간형 행사는 날짜별 회차 대신 기간 정보로 방문 날짜와 시간을 고른다.
  const sessions = period ? [] : mergeContiguousSessions(rawSessions.flatMap(splitVenues));
  const classification = classifyEvent({ ...raw, title, category, tags });
  const timeMode = period ? 'period' : sessions.length === 0 ? 'unknown'
    : ['fixed', 'multiple', 'flexible'].includes(raw.time_mode)
      ? raw.time_mode : sessions.length > 1 ? 'multiple' : 'fixed';
  const recommendedArrivalMinutes = [0, 15, 30, 60].includes(Number(raw.recommended_arrival_minutes))
    ? Number(raw.recommended_arrival_minutes) : 15;
  return {
    id: randomUUID(), title, category, tags, ...classification,
    timeMode, recommendedArrivalMinutes,
    description: String(raw.description || '').trim().slice(0, 500),
    applicationDeadline: typeof raw.application_deadline === 'string' &&
      hasTimezone(raw.application_deadline) && Number.isFinite(Date.parse(raw.application_deadline))
      ? raw.application_deadline : null,
    participationFee: String(raw.participation_fee || '').trim().slice(0, 100) || null,
    fieldStatus: {
      applicationDeadline: typeof raw.application_deadline === 'string' &&
        hasTimezone(raw.application_deadline) && Number.isFinite(Date.parse(raw.application_deadline)) ? 'known' : 'unknown',
      participationFee: raw.participation_fee ? 'known' : 'unknown',
      time: sessions.length || period ? 'known' : 'unknown',
    },
    sessions, period,
    needsManualDetails: sessions.length === 0 && !period,
  };
}

export function validateSavedEvent(body) {
  const title = String(body.title || '').trim().slice(0, 120);
  const venue = String(body.venue || '').trim().slice(0, 160);
  const start = Date.parse(body.startsAt);
  const end = Date.parse(body.endsAt);
  if (!title || !venue || !hasTimezone(String(body.startsAt || '')) || !hasTimezone(String(body.endsAt || '')) || !Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
    throw invalid('행사 이름, 장소, 올바른 시작·종료 시간이 필요해요.');
  }
  if (end - start > 7 * 24 * 60 * 60 * 1000) throw invalid('행사 기간이 너무 길어요.');
  const calendarId = typeof body.calendarId === 'string' ? body.calendarId.trim().slice(0, 256) : null;
  const calendarEventId = typeof body.calendarEventId === 'string' ? body.calendarEventId.trim().slice(0, 256) : null;
  if (Boolean(calendarId) !== Boolean(calendarEventId)) throw invalid('캘린더 연결 정보가 올바르지 않아요.');
  const reminderMinutes = body.reminderMinutes == null ? null : Number(body.reminderMinutes);
  if (reminderMinutes != null && ![-1, 15, 60, 1440].includes(reminderMinutes)) throw invalid('알림 설정이 올바르지 않아요.');
  const tags = (Array.isArray(body.tags) ? body.tags : []).filter((tag) => typeof tag === 'string')
    .map((tag) => tag.trim().slice(0, 40)).filter(Boolean).slice(0, 8);
  const applicationDeadline = body.applicationDeadline == null ? null : String(body.applicationDeadline);
  if (applicationDeadline && (!hasTimezone(applicationDeadline) || !Number.isFinite(Date.parse(applicationDeadline)))) throw invalid('신청 마감일이 올바르지 않아요.');
  const sourceUrl = typeof body.sourceUrl === 'string' && /^https:\/\//.test(body.sourceUrl) ? body.sourceUrl.slice(0, 500) : null;
  const latitude = Number(body.locationLatitude), longitude = Number(body.locationLongitude);
  const hasCoordinates = Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
    Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;
  const classification = classifyEvent(body);
  return {
    id: randomUUID(), title, venue,
    startsAt: new Date(start).toISOString(), endsAt: new Date(end).toISOString(),
    category: categories.includes(body.category) ? body.category : '기타',
    tags, ...classification, applicationDeadline: applicationDeadline ? new Date(applicationDeadline).toISOString() : null,
    participationFee: String(body.participationFee || '').trim().slice(0, 100) || null,
    locationAddress: String(body.locationAddress || '').trim().slice(0, 200) || null, sourceUrl,
    locationLatitude: hasCoordinates ? latitude : null,
    locationLongitude: hasCoordinates ? longitude : null,
    description: String(body.description || '').trim().slice(0, 500),
    calendarId, calendarEventId, reminderMinutes,
    createdAt: new Date().toISOString(),
  };
}

export function recommendations(profile, catalog, now = Date.now()) {
  const saved = profile.saved || [];
  if (saved.length === 0) return [];
  const counts = Object.create(null);
  for (const event of saved) counts[event.category] = (counts[event.category] || 0) + 1;
  const existing = new Set(saved.map((event) => `${event.title}|${event.startsAt}`));
  return catalog
    .filter((event) => Date.parse(event.endsAt) > now && !existing.has(`${event.title}|${event.startsAt}`) && counts[event.category] > 0)
    .map((event) => ({ ...event, score: counts[event.category] || 0 }))
    .sort((a, b) => b.score - a.score || Date.parse(a.startsAt) - Date.parse(b.startsAt))
    .slice(0, 12);
}
