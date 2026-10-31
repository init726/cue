-- Approximate activity-area and public event coordinates for distance-based recommendations.
-- Exact device location and birth dates are never stored.
alter table public.profiles
  add column region_latitude double precision,
  add column region_longitude double precision,
  add constraint profile_region_coordinates check (
    (region_latitude is null and region_longitude is null) or
    (region_latitude between -90 and 90 and region_longitude between -180 and 180));

alter table public.events
  add column location_latitude double precision,
  add column location_longitude double precision,
  add constraint event_location_coordinates check (
    (location_latitude is null and location_longitude is null) or
    (location_latitude between -90 and 90 and location_longitude between -180 and 180));

create index events_location_idx on public.events(location_latitude, location_longitude)
  where location_latitude is not null and location_longitude is not null;

create or replace function public.cue_share_event(source_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  source public.events%rowtype;
  context public.profiles%rowtype;
  shared_id uuid;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select e.* into source from public.events e join public.user_events ue on ue.event_id=e.id
    where e.id=source_id and e.owner_user_id=actor and ue.user_id=actor and ue.status in ('saved','completed');
  if not found then return null; end if;
  select * into context from public.profiles where user_id=actor;
  insert into public.events(title,description,category,tags,format,domains,participation_fee,
    start_at,end_at,application_deadline,location_name,location_latitude,location_longitude,source_url,source_type,
    origin_kind,sharing_user_id,share_source_event_id,community_school,community_region,community_age_band)
  values(source.title,source.description,source.category,source.tags,source.format,source.domains,source.participation_fee,
    source.start_at,source.end_at,source.application_deadline,source.location_name,
    round(source.location_latitude::numeric,2),round(source.location_longitude::numeric,2),source.source_url,'catalog',
    'shared',actor,source_id,context.school,context.region,context.age_band)
  on conflict (sharing_user_id,share_source_event_id) do update set
    title=excluded.title,description=excluded.description,category=excluded.category,tags=excluded.tags,
    format=excluded.format,domains=excluded.domains,participation_fee=excluded.participation_fee,
    start_at=excluded.start_at,end_at=excluded.end_at,application_deadline=excluded.application_deadline,
    location_name=excluded.location_name,location_latitude=excluded.location_latitude,
    location_longitude=excluded.location_longitude,source_url=excluded.source_url,
    community_school=excluded.community_school,community_region=excluded.community_region,
    community_age_band=excluded.community_age_band,updated_at=now()
  returning id into shared_id;
  return jsonb_build_object('id',shared_id);
end;
$$;
