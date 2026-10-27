import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

// Optional real PostgreSQL engine check; no production credentials or network.
test('PostgreSQL sharing migration enforces RLS, RPC ownership and context updates',
  { skip: !process.env.CUE_PGLITE_MODULE }, async () => {
    const { PGlite } = await import(process.env.CUE_PGLITE_MODULE);
    const db = new PGlite();
    const a = '11111111-1111-1111-1111-111111111111';
    const b = '22222222-2222-2222-2222-222222222222';
    const event = '33333333-3333-3333-3333-333333333333';
    try {
      await db.exec(`
        create role anon; create role authenticated; create role service_role bypassrls;
        create schema auth;
        create table auth.users(id uuid primary key);
        create function auth.uid() returns uuid language sql stable as
          $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
        grant usage on schema public, auth to authenticated;
      `);
      for (const file of ['20260919000000_cue_memory.sql', '20260920000000_event_topics.sql', '20261028000000_community_sharing.sql']) {
        const sql = await fs.readFile(new URL(`../../supabase/migrations/${file}`, import.meta.url), 'utf8');
        await db.exec(sql.replace('create extension if not exists pgcrypto;', ''));
      }
      await db.exec(`insert into auth.users values('${a}'),('${b}');
        insert into public.events(id,owner_user_id,title,category,start_at,end_at,location_name,source_type)
          values('${event}','${a}','Poster','기타','2099-01-01T01:00:00Z','2099-01-01T02:00:00Z','School','scan');
        insert into public.user_events(user_id,event_id,status,origin,calendar_id,calendar_event_id)
          values('${a}','${event}','saved','scan','private-calendar','private-id');
        set role authenticated;
        set request.jwt.claim.sub='${b}';`);
      assert.equal((await db.query('select public.cue_share_event($1) as value', [event])).rows[0].value, null);
      assert.equal((await db.query('select * from public.events where id=$1', [event])).rows.length, 0);
      await assert.rejects(db.exec(`insert into public.events(title,category,start_at,end_at,location_name,source_type)
        values('Unauthorized','기타','2099-01-01','2099-01-02','Here','catalog')`));
      await db.exec(`set request.jwt.claim.sub='${a}'; update public.profiles set school='Campus A' where user_id='${a}';`);
      const shared = (await db.query('select public.cue_share_event($1) as value', [event])).rows[0].value;
      assert.ok(shared.id);
      assert.equal((await db.query('select public.cue_share_event($1) as value', [event])).rows[0].value.id, shared.id);
      await db.exec(`set request.jwt.claim.sub='${b}';`);
      await db.query('select public.cue_unshare_event($1)', [event]);
      assert.equal((await db.query('select * from public.events where id=$1', [shared.id])).rows.length, 1);
      await db.exec(`set request.jwt.claim.sub='${a}'; update public.profiles set school='Campus B' where user_id='${a}';`);
      assert.equal((await db.query('select community_school from public.events where id=$1', [shared.id])).rows[0].community_school, 'Campus B');
      await db.query('select public.cue_unshare_event($1)', [event]);
      assert.equal((await db.query('select * from public.events where id=$1', [shared.id])).rows.length, 0);
      assert.equal((await db.query('select * from public.user_events where event_id=$1', [event])).rows.length, 1);
    } finally { await db.close(); }
  });
