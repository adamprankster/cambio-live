-- Read-only post-upgrade checks for the SQL Editor.
-- Expected: no public SECURITY DEFINER game functions.
select n.nspname as schema, p.proname, p.prosecdef
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef;

-- Expected: false / false for each hidden table.
select t,
 has_table_privilege('authenticated','public.'||t,'SELECT') as players_can_read,
 has_table_privilege('anon','public.'||t,'SELECT') as unauthenticated_can_read
from unnest(array['game_cards','turn_state','round_scores']) t;

-- Expected: all three tables present.
select tablename from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public'
and tablename in ('rooms','room_players','game_state');

-- Expected: all three main new entry points exist.
select to_regprocedure('public.get_game_view(text)') as game_view,
 to_regprocedure('public.ready_for_round(text)') as ready,
 to_regprocedure('public.slam_card(text,integer,bigint)') as slam;

-- Expected: no private functions with an unset search_path.
select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='private' and not exists(
 select 1 from unnest(p.proconfig) c where c like 'search_path=%'
);
