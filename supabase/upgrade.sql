-- Apply before deploying the new frontend. Existing rooms and hands are preserved.
-- Transaction prevents a partially applied API contract.
begin;
lock table public.rooms in access exclusive mode;
alter table public.rooms add column if not exists score_limit int not null default 50;
alter table public.rooms add column if not exists caller_bonus int not null default 5;
alter table public.rooms add column if not exists caller_penalty int not null default 10;
alter table public.rooms add column if not exists game_over boolean not null default false;
alter table public.room_players add column if not exists first_turn_started boolean not null default true;
alter table public.room_players add column if not exists initial_ready boolean not null default false;
alter table public.game_cards add column if not exists discard_order bigint;
create sequence if not exists private.discard_sequence;
with ordered as (select id,row_number() over(order by created_at,id) n from public.game_cards where zone='discard')
update public.game_cards c set discard_order=o.n from ordered o where c.id=o.id and c.discard_order is null;
select setval('private.discard_sequence',greatest(coalesce((select max(discard_order) from public.game_cards),0)+1,1));
alter table public.turn_state add column if not exists draw_source text;
alter table public.turn_state add column if not exists peeked_card_id uuid;
alter table public.turn_state add column if not exists peeked_label text;
-- Old rounds have already dealt cards. Do not reopen their initial peeks.
-- The old client only drew from the deck, so reserved draws retain that source.
update public.turn_state set draw_source='deck' where drawn_card_id is not null and draw_source is null;
update public.turn_state t set peeked_card_id=c.id,peeked_label=private.card_label(c.rank,c.suit)
from public.game_cards c where t.pending_ability='black_king_decide' and t.peeked_card_id is null
and c.room_code=t.room_code and c.zone='hand' and c.owner_user_id=t.peeked_target_user_id and c.position=t.peeked_target_position;
create table if not exists public.round_scores (
 room_code text not null references public.rooms(code) on delete cascade,
 round_number int not null, user_id uuid not null, name text not null, round_score int not null,
 primary key(room_code,round_number,user_id)
);
alter table public.round_scores enable row level security;
revoke all on public.round_scores from public, anon, authenticated;
alter table public.round_scores add column if not exists raw_score int not null default 0;
alter table public.round_scores add column if not exists call_adjustment int not null default 0;


CREATE OR REPLACE FUNCTION private.is_room_member(p_room text, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.room_players where room_code=p_room and user_id=p_user); $function$
;

CREATE OR REPLACE FUNCTION private.is_room_host(p_room text, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.rooms where code=p_room and host_user_id=p_user); $function$
;

CREATE OR REPLACE FUNCTION private.card_label(p_rank text, p_suit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select case when p_rank='K' then (case when p_suit in ('♥','♦') then 'Red K' else 'Black K' end) else p_rank||p_suit end; $function$
;

CREATE OR REPLACE FUNCTION private.card_points(p_rank text, p_suit text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$ select case when p_rank='K' and p_suit in ('♥','♦') then -1 when p_rank in ('J','Q','K') then 10 when p_rank='A' then 1 else p_rank::int end; $function$
;

CREATE OR REPLACE FUNCTION private.card_ability(p_rank text, p_suit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select case when p_rank in ('7','8') then 'peek_own' when p_rank in ('9','10') then 'peek_other' when p_rank in ('J','Q') then 'blind_swap' when p_rank='K' and p_suit in ('♠','♣') then 'black_king' else 'none' end; $function$
;

CREATE OR REPLACE FUNCTION private.random_room_code()
 RETURNS text
 LANGUAGE plpgsql
AS $function$ declare chars text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; out_code text:=''; begin for i in 1..6 loop out_code:=out_code||substr(chars,1+floor(random()*length(chars))::int,1); end loop; return out_code; end; $function$
;

CREATE OR REPLACE FUNCTION private.build_deck(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare s text; r text; idx int:=0; begin delete from public.game_cards where room_code=p_room_code; foreach s in array array['♠','♥','♦','♣'] loop foreach r in array array['A','2','3','4','5','6','7','8','9','10','J','Q','K'] loop idx:=idx+1; insert into public.game_cards(room_code,zone,rank,suit,deck_order) values(p_room_code,'deck',r,s,idx); end loop; end loop; with shuffled as (select id,row_number() over(order by random()) rn from public.game_cards where room_code=p_room_code and zone='deck') update public.game_cards c set deck_order=s.rn from shuffled s where c.id=s.id; end; $function$
;

CREATE OR REPLACE FUNCTION public.create_room(p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c text; begin if auth.uid() is null then raise exception 'Not signed in'; end if; if p_name is null or length(trim(p_name))<1 or length(trim(p_name))>18 then raise exception 'Name must be 1-18 characters'; end if; loop c:=private.random_room_code(); exit when not exists(select 1 from public.rooms where code=c); end loop; insert into public.rooms(code,host_user_id) values(c,auth.uid()); insert into public.room_players(room_code,user_id,name,seat) values(c,auth.uid(),trim(p_name),0); return jsonb_build_object('room_code',c); end; $function$
;

CREATE OR REPLACE FUNCTION public.call_cambio(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare n int; begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'You can only call Cambio on your turn'; end if; if (select phase from public.game_state where room_code=p_room_code)<>'turn' then raise exception 'Finish the current action first'; end if; if (select cambio_called_by from public.rooms where code=p_room_code) is not null then raise exception 'Cambio has already been called'; end if; select count(*) into n from public.room_players where room_code=p_room_code; update public.rooms set cambio_called_by=auth.uid(),final_turns_remaining=n where code=p_room_code; perform private.advance_turn(p_room_code); end; $function$
;

CREATE OR REPLACE FUNCTION public.join_room(p_room_code text, p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c text:=upper(trim(p_room_code)); n int; next_seat int; begin perform 1 from public.rooms where code=c for update; if auth.uid() is null then raise exception 'Not signed in'; end if; if p_name is null or length(trim(p_name))<1 or length(trim(p_name))>18 then raise exception 'Name must be 1-18 characters'; end if; if not exists(select 1 from public.rooms where code=c and status='lobby') then raise exception 'Room not found or game already started'; end if; select count(*) into n from public.room_players where room_code=c; if n>=6 and not exists(select 1 from public.room_players where room_code=c and user_id=auth.uid()) then raise exception 'Room is full'; end if; if exists(select 1 from public.room_players where room_code=c and user_id=auth.uid()) then update public.room_players set name=trim(p_name) where room_code=c and user_id=auth.uid(); else select coalesce(max(seat),-1)+1 into next_seat from public.room_players where room_code=c; insert into public.room_players(room_code,user_id,name,seat) values(c,auth.uid(),trim(p_name),next_seat); end if; return jsonb_build_object('room_code',c); end; $function$
;

CREATE OR REPLACE FUNCTION public.start_game(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare p record; c record; topc record; first_user uuid; current_round int; begin perform private.lock_member(p_room_code); if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Only the host can start'; end if; if (select count(*) from public.room_players where room_code=p_room_code)<2 then raise exception 'Need at least 2 players'; end if; select coalesce(round_number,0)+1 into current_round from public.game_state where room_code=p_room_code; if current_round is null then current_round:=1; end if; if (select game_over from public.rooms where code=p_room_code) then raise exception 'The match is over. Start a new match.'; end if; if (select status from public.rooms where code=p_room_code)='playing' then raise exception 'Round already in progress'; end if; perform private.build_deck(p_room_code); for p in select * from public.room_players where room_code=p_room_code order by seat loop for i in 0..3 loop select * into c from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='hand',owner_user_id=p.user_id,position=i,deck_order=null where id=c.id; end loop; end loop; select * into topc from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='discard',deck_order=null,created_at=clock_timestamp(),discard_order=nextval('private.discard_sequence') where id=topc.id; select user_id into first_user from public.room_players where room_code=p_room_code order by seat limit 1; insert into public.game_state(room_code,current_turn_user_id,deck_count,discard_top_label,phase,round_number) values(p_room_code,first_user,(select count(*) from public.game_cards where room_code=p_room_code and zone='deck'),private.card_label(topc.rank,topc.suit),'waiting',current_round) on conflict(room_code) do update set current_turn_user_id=excluded.current_turn_user_id,deck_count=excluded.deck_count,discard_top_label=excluded.discard_top_label,phase='waiting',round_number=excluded.round_number,updated_at=now(); insert into public.turn_state(room_code) values(p_room_code) on conflict(room_code) do update set drawn_card_id=null,drawn_by=null,pending_ability=null,ability_card_rank=null,ability_card_suit=null; update public.room_players set first_turn_started=false,initial_ready=false where room_code=p_room_code; update public.turn_state set peeked_card_id=null,peeked_label=null,peeked_target_user_id=null,peeked_target_position=null,draw_source=null where room_code=p_room_code; update public.rooms set status='playing',cambio_called_by=null,final_turns_remaining=null where code=p_room_code; end; $function$
;

CREATE OR REPLACE FUNCTION public.get_my_hand_view(p_room_code text)
 RETURNS TABLE("position" integer, visible_value text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin perform private.lock_member(p_room_code); if not private.is_room_member(p_room_code,auth.uid()) then raise exception 'Not in room'; end if; return query select c.position,null::text from public.game_cards c where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=auth.uid() order by c.position; end; $function$
;

CREATE OR REPLACE FUNCTION public.resolve_draw(p_room_code text, p_mode text, p_position integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare dc record; oldc record; ability text; begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if; if (select phase from public.game_state where room_code=p_room_code)<>'drawn' then raise exception 'No drawn card to resolve'; end if; select c.* into dc from public.game_cards c join public.turn_state t on t.drawn_card_id=c.id where t.room_code=p_room_code and t.drawn_by=auth.uid(); if dc.id is null then raise exception 'No drawn card'; end if; ability:=case when p_mode='discard' then private.card_ability(dc.rank,dc.suit) else 'none' end; if p_mode='discard' then update public.game_cards set zone='discard',owner_user_id=null,position=null,deck_order=null,created_at=clock_timestamp(),discard_order=nextval('private.discard_sequence') where id=dc.id; elsif p_mode='replace' then if p_position is null or p_position<0 then raise exception 'Invalid card position'; end if; select * into oldc from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_position; if oldc.id is null then raise exception 'Card not found'; end if; update public.game_cards set zone='discard',owner_user_id=null,position=null,deck_order=null,created_at=clock_timestamp(),discard_order=nextval('private.discard_sequence') where id=oldc.id; update public.game_cards set zone='hand',owner_user_id=auth.uid(),position=p_position,deck_order=null where id=dc.id; else raise exception 'Invalid choice'; end if; update public.turn_state set drawn_card_id=null,drawn_by=null,pending_ability=ability,ability_card_rank=dc.rank,ability_card_suit=dc.suit where room_code=p_room_code; perform private.refresh_public_state(p_room_code); if ability='none' then update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); else update public.game_state set phase='ability',updated_at=now() where room_code=p_room_code; end if; return jsonb_build_object('ability',ability); end; $function$
;

CREATE OR REPLACE FUNCTION public.peek_own_card(p_room_code text, p_position integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c record; begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if; if (select pending_ability from public.turn_state where room_code=p_room_code)is distinct from 'peek_own' then raise exception 'That ability is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'Not your turn'; end if; select * into c from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_position; if c.id is null then raise exception 'Card not found'; end if; update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); return jsonb_build_object('card_label',private.card_label(c.rank,c.suit)); end; $function$
;

CREATE OR REPLACE FUNCTION public.blind_swap(p_room_code text, p_own_position integer, p_target_user_id uuid, p_target_position integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare a uuid; b uuid; begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if; if (select pending_ability from public.turn_state where room_code=p_room_code)is distinct from 'blind_swap' then raise exception 'That ability is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'Not your turn'; end if; if p_target_user_id=auth.uid() then raise exception 'Choose another player'; end if; select id into a from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_own_position; select id into b from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=p_target_user_id and position=p_target_position; if a is null or b is null then raise exception 'Card not found'; end if; update public.game_cards set position=99 where id=a; update public.game_cards set owner_user_id=auth.uid(),position=p_own_position where id=b; update public.game_cards set owner_user_id=p_target_user_id,position=p_target_position where id=a; update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); end; $function$
;

CREATE OR REPLACE FUNCTION public.peek_other_card(p_room_code text, p_target_user_id uuid, p_position integer, p_swap_own_position integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c record; ability text;
begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if;
  select pending_ability into ability from public.turn_state where room_code=p_room_code;
  if ability is null or ability not in ('peek_other','black_king') then raise exception 'That ability is not active'; end if;
  if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'Not your turn'; end if;
  if p_target_user_id=auth.uid() then raise exception 'Choose another player'; end if;
  select * into c from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=p_target_user_id and position=p_position;
  if c.id is null then raise exception 'Card not found'; end if;
  if ability='peek_other' then
    update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code;
    perform private.advance_turn(p_room_code);
  else
    update public.turn_state set pending_ability='black_king_decide',peeked_target_user_id=p_target_user_id,peeked_target_position=p_position,peeked_card_id=c.id,peeked_label=private.card_label(c.rank,c.suit) where room_code=p_room_code;
  end if;
  return jsonb_build_object('card_label',private.card_label(c.rank,c.suit),'needs_decision',ability='black_king');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.black_king_decide(p_room_code text, p_swap boolean, p_own_position integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target_user uuid; target_pos int; a uuid; b uuid;
begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if;
  if (select pending_ability from public.turn_state where room_code=p_room_code)is distinct from 'black_king_decide' then raise exception 'No Black King decision is pending'; end if;
  if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'Not your turn'; end if;
  select peeked_target_user_id,peeked_target_position into target_user,target_pos from public.turn_state where room_code=p_room_code;
  if p_swap is null then raise exception 'Choose swap or keep'; end if; if p_swap then
    if p_own_position is null or p_own_position<0 then raise exception 'Choose one of your cards'; end if;
    select id into a from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_own_position;
    select id into b from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=target_user and position=target_pos and id=(select peeked_card_id from public.turn_state where room_code=p_room_code);
    if a is null or b is null then raise exception 'Card not found'; end if;
    update public.game_cards set position=99 where id=a;
    update public.game_cards set owner_user_id=auth.uid(),position=p_own_position where id=b;
    update public.game_cards set owner_user_id=target_user,position=target_pos where id=a;
  end if;
  update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null,peeked_target_user_id=null,peeked_target_position=null where room_code=p_room_code;
  perform private.advance_turn(p_room_code);
end;
$function$
;
-- Every action locks the same room row, so simultaneous draws/slams cannot race.
create or replace function private.lock_member(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.rooms where code=p_room_code for update;
 if auth.uid() is null or not private.is_room_member(p_room_code,auth.uid()) then raise exception 'Not in room'; end if;
end $$;

create or replace function private.refresh_public_state(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
declare topc public.game_cards;
begin
 select * into topc from public.game_cards c where c.room_code=p_room_code and zone='discard'
 and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id)
 order by discard_order desc nulls last limit 1;
 update public.game_state set deck_count=(select count(*) from public.game_cards c where c.room_code=p_room_code and zone='deck'
 and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id)),
 discard_top_label=case when topc.id is null then null else private.card_label(topc.rank,topc.suit) end,
 updated_at=clock_timestamp() where room_code=p_room_code;
end $$;

create or replace function private.finish_round(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
declare r public.rooms;
begin
 select * into r from public.rooms where code=p_room_code;
 with raw as (
 select p.user_id,p.name,g.round_number,coalesce(sum(private.card_points(c.rank,c.suit)),0)::int score
 from public.room_players p join public.game_state g on g.room_code=p.room_code
 left join public.game_cards c on c.room_code=p.room_code and c.owner_user_id=p.user_id and c.zone='hand'
 where p.room_code=p_room_code group by g.round_number,p.user_id,p.name
 ), rated as (
 select raw.*,case when user_id=r.cambio_called_by then
 case when score<(select min(other.score) from raw other where other.user_id<>raw.user_id) then -r.caller_bonus else r.caller_penalty end else 0 end adjustment from raw
 ), added as (
 insert into public.round_scores(room_code,round_number,user_id,name,round_score,raw_score,call_adjustment)
 select p_room_code,round_number,user_id,name,score+adjustment,score,adjustment from rated
 on conflict do nothing returning user_id,round_score)
 update public.room_players p set total_score=p.total_score+a.round_score from added a where p.room_code=p_room_code and p.user_id=a.user_id;
 update public.rooms set status='round_over',final_turns_remaining=0,game_over=exists(select 1 from public.room_players where room_code=p_room_code and total_score>=r.score_limit) where code=p_room_code;
 update public.game_state set phase='round_over',updated_at=clock_timestamp() where room_code=p_room_code;
 update public.turn_state set drawn_card_id=null,drawn_by=null,pending_ability=null,peeked_card_id=null,peeked_label=null where room_code=p_room_code;
end $$;

create or replace function private.advance_turn(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
declare cur uuid; nextu uuid; curseat int; finaln int;
begin
 select current_turn_user_id into cur from public.game_state where room_code=p_room_code;
 select seat into curseat from public.room_players where room_code=p_room_code and user_id=cur;
 select final_turns_remaining into finaln from public.rooms where code=p_room_code;
 if finaln is not null then
  if finaln<=1 then perform private.finish_round(p_room_code); return; end if;
  update public.rooms set final_turns_remaining=finaln-1 where code=p_room_code;
 end if;
 select user_id into nextu from public.room_players where room_code=p_room_code order by (seat>curseat) desc,seat limit 1;
 update public.room_players set first_turn_started=true where room_code=p_room_code and user_id=nextu;
 update public.turn_state set pending_ability=null,drawn_card_id=null,drawn_by=null,draw_source=null,peeked_label=null,peeked_card_id=null,peeked_target_user_id=null,peeked_target_position=null where room_code=p_room_code;
 update public.game_state set current_turn_user_id=nextu,phase='turn',updated_at=clock_timestamp() where room_code=p_room_code;
end $$;

create or replace function public.ready_for_round(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if (select phase from public.game_state where room_code=p_room_code) is distinct from 'waiting' then raise exception 'The round has already begun'; end if;
 update public.room_players set initial_ready=true where room_code=p_room_code and user_id=auth.uid();
 if not exists(select 1 from public.room_players where room_code=p_room_code and not initial_ready) then
  update public.room_players set first_turn_started=true where room_code=p_room_code and user_id=(select current_turn_user_id from public.game_state where room_code=p_room_code);
  update public.game_state set phase='turn',updated_at=clock_timestamp() where room_code=p_room_code;
 end if;
end $$;

create or replace function public.get_initial_peek(p_room_code text,p_positions int[])
returns table("position" int,card_label text) language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code) is distinct from 'playing'
 or (select first_turn_started from public.room_players where room_code=p_room_code and user_id=auth.uid()) is distinct from false then raise exception 'Initial peek is locked'; end if;
 if p_positions is null or cardinality(p_positions) not between 1 and 2 or not p_positions <@ array[2,3] or array_position(p_positions,null) is not null then raise exception 'Only bottom cards 3 and 4 may be viewed'; end if;
 return query select c.position,private.card_label(c.rank,c.suit) from public.game_cards c where c.room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and c.position=any(p_positions) order by c.position;
end $$;

create or replace function private.take_deck(p_room_code text) returns uuid
language plpgsql security definer set search_path='' as $$
declare picked uuid; top_id uuid;
begin
 select c.id into picked from public.game_cards c where c.room_code=p_room_code and zone='deck'
 and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id) order by deck_order limit 1;
 if picked is null then
  select c.id into top_id from public.game_cards c where c.room_code=p_room_code and zone='discard'
  and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id) order by discard_order desc nulls last limit 1;
  with shuffled as (select c.id,row_number() over(order by random()) n from public.game_cards c where c.room_code=p_room_code and zone='discard' and c.id is distinct from top_id
  and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id))
  update public.game_cards c set zone='deck',deck_order=s.n,discard_order=null from shuffled s where c.id=s.id;
  select c.id into picked from public.game_cards c where c.room_code=p_room_code and zone='deck' and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id) order by deck_order limit 1;
 end if;
 return picked;
end $$;

create or replace function public.draw_from(p_room_code text,p_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.game_cards; picked uuid;
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code) is distinct from 'playing'
 or (select phase from public.game_state where room_code=p_room_code) is distinct from 'turn'
 or (select current_turn_user_id from public.game_state where room_code=p_room_code) is distinct from auth.uid() then raise exception 'You cannot draw now'; end if;
 if p_source='deck' then picked:=private.take_deck(p_room_code);
 elsif p_source='discard' then select id into picked from public.game_cards where room_code=p_room_code and zone='discard' order by discard_order desc nulls last limit 1;
 else raise exception 'Choose deck or discard'; end if;
 if picked is null then raise exception 'This pile is empty. Draw from the other pile or call Cambio.'; end if;
 select * into c from public.game_cards where id=picked;
 update public.turn_state set drawn_card_id=picked,drawn_by=auth.uid(),draw_source=p_source where room_code=p_room_code;
 update public.game_state set phase='drawn' where room_code=p_room_code;
 perform private.refresh_public_state(p_room_code);
 return jsonb_build_object('card_label',private.card_label(c.rank,c.suit));
end $$;
create or replace function public.draw_card(p_room_code text) returns jsonb language sql security invoker set search_path='' as $$select public.draw_from(p_room_code,'deck');$$;

create or replace function public.skip_ability(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if (select phase from public.game_state where room_code=p_room_code) is distinct from 'ability'
 or (select current_turn_user_id from public.game_state where room_code=p_room_code) is distinct from auth.uid() then raise exception 'No ability to skip'; end if;
 perform private.advance_turn(p_room_code);
end $$;

create or replace function public.slam_card(p_room_code text,p_position int,p_discard_order bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare mine public.game_cards; topc public.game_cards; penalty uuid; pos int;
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code) is distinct from 'playing'
 or (select phase from public.game_state where room_code=p_room_code)='waiting' then raise exception 'Slamming is not available now'; end if;
 select * into topc from public.game_cards c where c.room_code=p_room_code and zone='discard'
 and not exists(select 1 from public.turn_state t where t.room_code=p_room_code and t.drawn_card_id=c.id) order by discard_order desc nulls last limit 1;
 if topc.id is null or topc.discard_order is distinct from p_discard_order then raise exception 'Discard changed. Try again.'; end if;
 select * into mine from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_position;
 if mine.id is null then raise exception 'Card not found'; end if;
 if mine.rank=topc.rank then
  update public.game_cards set zone='discard',owner_user_id=null,position=null,discard_order=nextval('private.discard_sequence') where id=mine.id;
 else
  penalty:=private.take_deck(p_room_code);
  if penalty is null then raise exception 'No penalty card is available; slam was not accepted'; end if;
  select greatest(4,coalesce(max(position)+1,4)) into pos from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid();
  update public.game_cards set zone='hand',owner_user_id=auth.uid(),position=pos,deck_order=null where id=penalty;
 end if;
 perform private.refresh_public_state(p_room_code);
 return jsonb_build_object('matched',mine.rank=topc.rank,'penalty',mine.rank<>topc.rank);
end $$;

create or replace function public.get_round_scores(p_room_code text)
returns table(user_id uuid,name text,round_score int,total_score int)
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code) is distinct from 'round_over' then raise exception 'Round is not over'; end if;
 return query select p.user_id,p.name,s.round_score,p.total_score from public.room_players p
 join public.round_scores s on s.room_code=p.room_code and s.user_id=p.user_id
 join public.game_state g on g.room_code=s.room_code and g.round_number=s.round_number
 where p.room_code=p_room_code order by s.round_score,p.seat;
end $$;
create or replace function public.next_round(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if;
 if (select status from public.rooms where code=p_room_code) is distinct from 'round_over' then raise exception 'Round is not over'; end if;
 perform public.start_game(p_room_code);
end $$;
create or replace function public.return_to_lobby(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if;
 if (select status from public.rooms where code=p_room_code)='playing' then raise exception 'Finish the round first'; end if;
 update public.rooms set status='lobby',cambio_called_by=null,final_turns_remaining=null where code=p_room_code;
end $$;
create or replace function public.leave_room(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
declare h uuid;
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code)='playing' then raise exception 'A round is in progress. Close the page to disconnect and rejoin later.'; end if;
 select host_user_id into h from public.rooms where code=p_room_code;
 delete from public.room_players where room_code=p_room_code and user_id=auth.uid();
 if not exists(select 1 from public.room_players where room_code=p_room_code) then delete from public.rooms where code=p_room_code;
 elsif h=auth.uid() then update public.rooms set host_user_id=(select user_id from public.room_players where room_code=p_room_code order by seat limit 1) where code=p_room_code; end if;
end $$;

-- One consistent snapshot, with secrets only for the caller's authorized action.
create or replace function public.get_game_view(p_room_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.rooms; g public.game_state; t public.turn_state; own jsonb; players jsonb; drawn text; top_order bigint;
begin
 perform private.lock_member(p_room_code);
 select * into r from public.rooms where code=p_room_code;
 select * into g from public.game_state where room_code=p_room_code;
 select * into t from public.turn_state where room_code=p_room_code;
 select jsonb_agg(jsonb_build_object('position',c.position)) into own from public.game_cards c where c.room_code=p_room_code and zone='hand' and owner_user_id=auth.uid();
 select jsonb_agg(to_jsonb(p) || jsonb_build_object('positions',(select coalesce(jsonb_agg(c.position order by c.position),'[]') from public.game_cards c where c.room_code=p_room_code and zone='hand' and owner_user_id=p.user_id)) order by p.seat) into players from public.room_players p where p.room_code=p_room_code;
 if t.drawn_by=auth.uid() then select private.card_label(rank,suit) into drawn from public.game_cards where id=t.drawn_card_id; end if;
 select c.discard_order into top_order from public.game_cards c where c.room_code=p_room_code and zone='discard' and c.id is distinct from t.drawn_card_id order by c.discard_order desc nulls last limit 1;
 return jsonb_build_object('room',to_jsonb(r),'game',to_jsonb(g),'players',players,'hand',coalesce(own,'[]'),'me',auth.uid(),'drawn_label',drawn,'discard_order',top_order,
 'ability',case when g.current_turn_user_id=auth.uid() then t.pending_ability end,
 'round_details',case when r.status='round_over' then (select jsonb_agg(to_jsonb(s)) from public.round_scores s where s.room_code=p_room_code and s.round_number=g.round_number) end,
 'revealed_cards',case when r.status='round_over' then (select jsonb_agg(jsonb_build_object('user_id',owner_user_id,'position',position,'label',private.card_label(rank,suit))) from public.game_cards where room_code=p_room_code and zone='hand') end,
 'peeked_label',case when g.current_turn_user_id=auth.uid() and t.pending_ability='black_king_decide' then t.peeked_label end);
end $$;

create or replace function public.set_room_rules(p_room_code text,p_score_limit int,p_caller_bonus int,p_caller_penalty int) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if;
 if (select status from public.rooms where code=p_room_code) is distinct from 'lobby' then raise exception 'Change rules in the lobby'; end if;
 if p_score_limit is null or p_score_limit not between 10 and 500 or p_caller_bonus is null or p_caller_bonus not between 0 and 50 or p_caller_penalty is null or p_caller_penalty not between 0 and 50 then raise exception 'Invalid scoring settings'; end if;
 update public.rooms set score_limit=p_score_limit,caller_bonus=p_caller_bonus,caller_penalty=p_caller_penalty where code=p_room_code;
end $$;
create or replace function public.new_match(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if;
 if (select status from public.rooms where code=p_room_code) is distinct from 'round_over' or not (select game_over from public.rooms where code=p_room_code) then raise exception 'Finish this match first'; end if;
 delete from public.round_scores where room_code=p_room_code;
 update public.room_players set total_score=0 where room_code=p_room_code;
 update public.game_state set round_number=0 where room_code=p_room_code;
 update public.rooms set status='lobby',game_over=false,cambio_called_by=null,final_turns_remaining=null where code=p_room_code;
end $$;

-- Restrict old and new RPCs explicitly; internal helpers are never public APIs.
revoke all on public.game_cards,public.turn_state from public,anon,authenticated;
grant select on public.rooms,public.room_players,public.game_state to authenticated;
DO $$ declare f record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' loop
 execute format('revoke all on function %s from public, anon, authenticated',f.sig);
 end loop;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(array['create_room','join_room','start_game','get_my_hand_view','get_initial_peek','draw_card','draw_from','resolve_draw','peek_own_card','peek_other_card','blind_swap','black_king_decide','call_cambio','get_round_scores','next_round','return_to_lobby','leave_room','ready_for_round','skip_ability','slam_card','get_game_view','set_room_rules','new_match']) loop
 execute format('revoke all on function %s from public, anon',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
grant usage on schema private to authenticated;
grant execute on function private.is_room_member(text,uuid),private.is_room_host(text,uuid) to authenticated;
-- Public entry points are invoker wrappers. Privileged implementations live in
-- the non-exposed private schema and repeat all membership/action checks.
DO $$ declare f record; definition text; args text; begin
 for f in select p.oid,p.proname,pg_get_function_arguments(p.oid) arguments,
 pg_get_function_result(p.oid) result,p.proargnames,p.pronargs,p.proretset
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosecdef and p.proname=any(array[
 'create_room','join_room','start_game','get_my_hand_view','get_initial_peek','draw_from','resolve_draw',
 'peek_own_card','peek_other_card','blind_swap','black_king_decide','call_cambio','get_round_scores',
 'next_round','return_to_lobby','leave_room','ready_for_round','skip_ability','slam_card','get_game_view','set_room_rules','new_match']) loop
 definition:=pg_get_functiondef(f.oid);
 definition:=replace(definition,'FUNCTION public.'||f.proname||'(', 'FUNCTION private.rpc_'||f.proname||'(');
 execute definition;
 select string_agg(format('%I',x),',') into args from unnest(f.proargnames[1:f.pronargs]) x;
 execute format('create or replace function public.%I(%s) returns %s language sql security invoker set search_path=%L as %L',f.proname,f.arguments,f.result,'',
 'select '||case when f.proretset then '* from ' else '' end||'private.rpc_'||f.proname||'('||args||')');
 end loop;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'rpc\_%' escape '\' loop
 execute format('revoke all on function %s from public,anon',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
-- Record a finished legacy round once before the new frontend reads its ledger.
DO $$ declare r record; begin
 for r in select code from public.rooms where status='round_over' loop perform private.finish_round(r.code); end loop;
end $$;
create index if not exists game_cards_room_zone_idx on public.game_cards(room_code,zone);
create index if not exists game_cards_hand_idx on public.game_cards(room_code,owner_user_id,position) where zone='hand';
alter function private.card_label(text,text) set search_path='';
alter function private.card_points(text,text) set search_path='';
alter function private.card_ability(text,text) set search_path='';
alter function private.random_room_code() set search_path='';
-- Fresh projects and existing projects share the same Realtime publication.
DO $$ declare t text; begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 foreach t in array array['rooms','room_players','game_state'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t);
 end if;
 end loop;
 end if;
end $$;
notify pgrst, 'reload schema';
commit;
