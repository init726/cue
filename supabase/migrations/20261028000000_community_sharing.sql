-- Experimental public event sharing. Private calendar rows remain separate.
alter table public.profiles
  add column school text not null default '' check (length(school) <= 80),
  add column region text not null default '' check (length(region) <= 80),
  add column age_band text not null default '' check (age_band in ('','under20','20s','30s','40plus'));

alter table public.events
  add column origin_kind text not null default 'legacy' check (origin_kind in ('legacy','catalog','web','demo','shared')),
  add column sharing_user_id uuid references auth.users(id) on delete cascade,
  add column share_source_event_id uuid references public.events(id) on delete cascade,
  add column community_school text not null default '',
  add column community_region text not null default '',
  add column community_age_band text not null default '',
  add constraint shared_event_owner_unique unique(sharing_user_id,share_source_event_id),
  add constraint shared_event_source_check check (
    (origin_kind = 'shared' and source_type = 'catalog' and owner_user_id is null and sharing_user_id is not null and share_source_event_id is not null)
    or (origin_kind <> 'shared' and sharing_user_id is null and share_source_event_id is null));
alter table public.events alter column origin_kind set default 'catalog';

-- Only these authenticated RPCs can publish a catalog copy.
create function public.cue_share_event(source_id uuid)
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
    start_at,end_at,application_deadline,location_name,source_url,source_type,
    origin_kind,sharing_user_id,share_source_event_id,community_school,community_region,community_age_band)
  values(source.title,source.description,source.category,source.tags,source.format,source.domains,source.participation_fee,
    source.start_at,source.end_at,source.application_deadline,source.location_name,source.source_url,'catalog',
    'shared',actor,source_id,context.school,context.region,context.age_band)
  on conflict (sharing_user_id,share_source_event_id) do update set
    title=excluded.title,description=excluded.description,category=excluded.category,tags=excluded.tags,
    format=excluded.format,domains=excluded.domains,participation_fee=excluded.participation_fee,
    start_at=excluded.start_at,end_at=excluded.end_at,application_deadline=excluded.application_deadline,
    location_name=excluded.location_name,source_url=excluded.source_url,
    community_school=excluded.community_school,community_region=excluded.community_region,
    community_age_band=excluded.community_age_band,updated_at=now()
  returning id into shared_id;
  return jsonb_build_object('id',shared_id);
end;
$$;

create function public.cue_unshare_event(source_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from public.events where sharing_user_id=auth.uid() and share_source_event_id=source_id;
  return true;
end;
$$;
revoke all on function public.cue_share_event(uuid), public.cue_unshare_event(uuid) from public,anon;
grant execute on function public.cue_share_event(uuid), public.cue_unshare_event(uuid) to authenticated;

-- Context is used for matching, never displayed as the sharer's identity.
create function public.cue_update_shared_context()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.events set community_school=new.school,community_region=new.region,community_age_band=new.age_band
    where sharing_user_id=new.user_id;
  return new;
end;
$$;
create trigger cue_shared_context after update of school,region,age_band on public.profiles
  for each row execute function public.cue_update_shared_context();
