-- Link event venues to a verified map place (Kakao Local) so the same venue is one place across users.
-- Only a place the user picked from map search is "verified"; typed venue names stay unverified.
alter table public.events
  add column if not exists place_provider text,
  add column if not exists place_id text,
  add column if not exists place_category text;

alter table public.events drop constraint if exists event_place_link;
alter table public.events add constraint event_place_link check (
  (place_provider is null and place_id is null) or
  (place_provider = 'kakao' and place_id ~ '^[0-9]{1,20}$'));

create index if not exists events_place_idx on public.events(place_provider, place_id)
  where place_id is not null;

-- Sharing keeps the venue's public address and exact coordinates only for verified public places.
-- Unverified venues (which may be a home or a private room) share the name and ~1km coordinates as before.
create or replace function public.cue_share_event(source_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  source public.events%rowtype;
  context public.profiles%rowtype;
  verified boolean;
  shared_id uuid;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select e.* into source from public.events e join public.user_events ue on ue.event_id=e.id
    where e.id=source_id and e.owner_user_id=actor and ue.user_id=actor and ue.status in ('saved','completed');
  if not found then return null; end if;
  select * into context from public.profiles where user_id=actor;
  verified := source.place_id is not null;
  insert into public.events(title,description,category,tags,format,domains,participation_fee,
    start_at,end_at,application_deadline,location_name,location_address,location_latitude,location_longitude,
    place_provider,place_id,place_category,source_url,source_type,
    origin_kind,sharing_user_id,share_source_event_id,community_school,community_region,community_age_band)
  values(source.title,source.description,source.category,source.tags,source.format,source.domains,source.participation_fee,
    source.start_at,source.end_at,source.application_deadline,source.location_name,
    case when verified then source.location_address end,
    case when verified then source.location_latitude else round(source.location_latitude::numeric,2) end,
    case when verified then source.location_longitude else round(source.location_longitude::numeric,2) end,
    source.place_provider,source.place_id,source.place_category,source.source_url,'catalog',
    'shared',actor,source_id,context.school,context.region,context.age_band)
  on conflict (sharing_user_id,share_source_event_id) do update set
    title=excluded.title,description=excluded.description,category=excluded.category,tags=excluded.tags,
    format=excluded.format,domains=excluded.domains,participation_fee=excluded.participation_fee,
    start_at=excluded.start_at,end_at=excluded.end_at,application_deadline=excluded.application_deadline,
    location_name=excluded.location_name,location_address=excluded.location_address,
    location_latitude=excluded.location_latitude,location_longitude=excluded.location_longitude,
    place_provider=excluded.place_provider,place_id=excluded.place_id,place_category=excluded.place_category,
    source_url=excluded.source_url,
    community_school=excluded.community_school,community_region=excluded.community_region,
    community_age_band=excluded.community_age_band,updated_at=now()
  returning id into shared_id;
  return jsonb_build_object('id',shared_id);
end;
$$;
