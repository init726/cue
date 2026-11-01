-- Topics a person picks during onboarding or in settings, used as interests before any history exists.
alter table public.profiles
  add column if not exists favorite_topics text[] not null default '{}';

alter table public.profiles drop constraint if exists profile_favorite_topics_size;
alter table public.profiles add constraint profile_favorite_topics_size
  check (cardinality(favorite_topics) <= 10);
