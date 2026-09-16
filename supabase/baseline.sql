-- Recovered live schema. NEW databases only; then apply migrations.
create schema if not exists private;

create table if not exists public.rooms (
"code" text not null,
"host_user_id" uuid not null,
"status" text default 'lobby'::text not null,
"created_at" timestamp with time zone default now() not null,
"cambio_called_by" uuid,
"final_turns_remaining" integer,
primary key (code)
);

alter table public.rooms enable row level security;

create table if not exists public.room_players (
"room_code" text not null,
"user_id" uuid not null,
"name" text not null,
"seat" integer not null,
"joined_at" timestamp with time zone default now() not null,
"total_score" integer default 0 not null,
primary key (room_code,user_id),
foreign key(room_code) references public.rooms(code) on delete cascade
);

alter table public.room_players enable row level security;

create table if not exists public.game_state (
"room_code" text not null,
"current_turn_user_id" uuid,
"deck_count" integer default 0 not null,
"discard_top_label" text,
"phase" text default 'waiting'::text not null,
"round_number" integer default 1 not null,
"updated_at" timestamp with time zone default now() not null,
primary key (room_code),
foreign key(room_code) references public.rooms(code) on delete cascade
);

alter table public.game_state enable row level security;

create table if not exists public.game_cards (
"id" uuid default gen_random_uuid() not null,
"room_code" text not null,
"zone" text not null,
"owner_user_id" uuid,
"position" integer,
"rank" text not null,
"suit" text not null,
"deck_order" integer,
"created_at" timestamp with time zone default now() not null,
primary key (id),
foreign key(room_code) references public.rooms(code) on delete cascade
);

alter table public.game_cards enable row level security;

create table if not exists public.turn_state (
"room_code" text not null,
"drawn_card_id" uuid,
"drawn_by" uuid,
"pending_ability" text,
"ability_card_rank" text,
"ability_card_suit" text,
"peeked_target_user_id" uuid,
"peeked_target_position" integer,
primary key (room_code),
foreign key(room_code) references public.rooms(code) on delete cascade
);

alter table public.turn_state enable row level security;

CREATE OR REPLACE FUNCTION private.is_room_member(p_room text, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ select exists(select 1 from public.room_players where room_code=p_room and user_id=p_user); $function$
;

CREATE OR REPLACE FUNCTION private.is_room_host(p_room text, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
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
 SET search_path TO 'public', 'private'
AS $function$ declare s text; r text; idx int:=0; begin delete from public.game_cards where room_code=p_room_code; foreach s in array array['♠','♥','♦','♣'] loop foreach r in array array['A','2','3','4','5','6','7','8','9','10','J','Q','K'] loop idx:=idx+1; insert into public.game_cards(room_code,zone,rank,suit,deck_order) values(p_room_code,'deck',r,s,idx); end loop; end loop; with shuffled as (select id,row_number() over(order by random()) rn from public.game_cards where room_code=p_room_code and zone='deck') update public.game_cards c set deck_order=s.rn from shuffled s where c.id=s.id; end; $function$
;

CREATE OR REPLACE FUNCTION private.refresh_public_state(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare topc record; begin select * into topc from public.game_cards where room_code=p_room_code and zone='discard' order by created_at desc,id desc limit 1; update public.game_state set deck_count=(select count(*) from public.game_cards where room_code=p_room_code and zone='deck'),discard_top_label=case when topc.id is null then null else private.card_label(topc.rank,topc.suit) end,updated_at=now() where room_code=p_room_code; end; $function$
;

CREATE OR REPLACE FUNCTION private.advance_turn(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare cur uuid; nextu uuid; curseat int; finaln int; begin select current_turn_user_id into cur from public.game_state where room_code=p_room_code; select seat into curseat from public.room_players where room_code=p_room_code and user_id=cur; select user_id into nextu from public.room_players where room_code=p_room_code and seat>curseat order by seat limit 1; if nextu is null then select user_id into nextu from public.room_players where room_code=p_room_code order by seat limit 1; end if; select final_turns_remaining into finaln from public.rooms where code=p_room_code; if finaln is not null then finaln:=finaln-1; if finaln<=0 then update public.rooms set status='round_over',final_turns_remaining=0 where code=p_room_code; update public.game_state set phase='round_over',updated_at=now() where room_code=p_room_code; return; else update public.rooms set final_turns_remaining=finaln where code=p_room_code; end if; end if; update public.game_state set current_turn_user_id=nextu,phase='turn',updated_at=now() where room_code=p_room_code; end; $function$
;

CREATE OR REPLACE FUNCTION public.create_room(p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare c text; begin if auth.uid() is null then raise exception 'Not signed in'; end if; if length(trim(p_name))<1 or length(trim(p_name))>18 then raise exception 'Name must be 1-18 characters'; end if; loop c:=private.random_room_code(); exit when not exists(select 1 from public.rooms where code=c); end loop; insert into public.rooms(code,host_user_id) values(c,auth.uid()); insert into public.room_players(room_code,user_id,name,seat) values(c,auth.uid(),trim(p_name),0); return jsonb_build_object('room_code',c); end; $function$
;

CREATE OR REPLACE FUNCTION public.call_cambio(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare n int; begin if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'You can only call Cambio on your turn'; end if; if (select phase from public.game_state where room_code=p_room_code)<>'turn' then raise exception 'Finish the current action first'; end if; if (select cambio_called_by from public.rooms where code=p_room_code) is not null then raise exception 'Cambio has already been called'; end if; select count(*) into n from public.room_players where room_code=p_room_code; update public.rooms set cambio_called_by=auth.uid(),final_turns_remaining=n where code=p_room_code; perform private.advance_turn(p_room_code); end; $function$
;

CREATE OR REPLACE FUNCTION public.join_room(p_room_code text, p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare c text:=upper(trim(p_room_code)); n int; next_seat int; begin if auth.uid() is null then raise exception 'Not signed in'; end if; if length(trim(p_name))<1 or length(trim(p_name))>18 then raise exception 'Name must be 1-18 characters'; end if; if not exists(select 1 from public.rooms where code=c and status='lobby') then raise exception 'Room not found or game already started'; end if; select count(*) into n from public.room_players where room_code=c; if n>=6 and not exists(select 1 from public.room_players where room_code=c and user_id=auth.uid()) then raise exception 'Room is full'; end if; if exists(select 1 from public.room_players where room_code=c and user_id=auth.uid()) then update public.room_players set name=trim(p_name) where room_code=c and user_id=auth.uid(); else select coalesce(max(seat),-1)+1 into next_seat from public.room_players where room_code=c; insert into public.room_players(room_code,user_id,name,seat) values(c,auth.uid(),trim(p_name),next_seat); end if; return jsonb_build_object('room_code',c); end; $function$
;

CREATE OR REPLACE FUNCTION public.start_game(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare p record; c record; topc record; first_user uuid; current_round int; begin if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Only the host can start'; end if; if (select count(*) from public.room_players where room_code=p_room_code)<2 then raise exception 'Need at least 2 players'; end if; select coalesce(round_number,0)+1 into current_round from public.game_state where room_code=p_room_code; if current_round is null then current_round:=1; end if; perform private.build_deck(p_room_code); for p in select * from public.room_players where room_code=p_room_code order by seat loop for i in 0..3 loop select * into c from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='hand',owner_user_id=p.user_id,position=i,deck_order=null where id=c.id; end loop; end loop; select * into topc from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='discard',deck_order=null,created_at=now() where id=topc.id; select user_id into first_user from public.room_players where room_code=p_room_code order by seat limit 1; insert into public.game_state(room_code,current_turn_user_id,deck_count,discard_top_label,phase,round_number) values(p_room_code,first_user,(select count(*) from public.game_cards where room_code=p_room_code and zone='deck'),private.card_label(topc.rank,topc.suit),'turn',current_round) on conflict(room_code) do update set current_turn_user_id=excluded.current_turn_user_id,deck_count=excluded.deck_count,discard_top_label=excluded.discard_top_label,phase='turn',round_number=excluded.round_number,updated_at=now(); insert into public.turn_state(room_code) values(p_room_code) on conflict(room_code) do update set drawn_card_id=null,drawn_by=null,pending_ability=null,ability_card_rank=null,ability_card_suit=null; update public.rooms set status='playing',cambio_called_by=null,final_turns_remaining=null where code=p_room_code; end; $function$
;

CREATE OR REPLACE FUNCTION public.get_my_hand_view(p_room_code text)
 RETURNS TABLE("position" integer, visible_value text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ begin if not private.is_room_member(p_room_code,auth.uid()) then raise exception 'Not in room'; end if; return query select c.position,null::text from public.game_cards c where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=auth.uid() order by c.position; end; $function$
;

CREATE OR REPLACE FUNCTION public.get_initial_peek(p_room_code text, p_positions integer[])
 RETURNS TABLE("position" integer, card_label text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ begin if not private.is_room_member(p_room_code,auth.uid()) then raise exception 'Not in room'; end if; if coalesce(array_length(p_positions,1),0)>2 then raise exception 'You may peek at only two starting cards'; end if; return query select c.position,private.card_label(c.rank,c.suit) from public.game_cards c where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=auth.uid() and c.position=any(p_positions) order by c.position; end; $function$
;

CREATE OR REPLACE FUNCTION public.draw_card(p_room_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare c record; begin if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'Not your turn'; end if; if (select phase from public.game_state where room_code=p_room_code)<>'turn' then raise exception 'Finish the current action first'; end if; select * into c from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; if c.id is null then raise exception 'Deck is empty'; end if; update public.turn_state set drawn_card_id=c.id,drawn_by=auth.uid() where room_code=p_room_code; update public.game_state set phase='drawn',updated_at=now() where room_code=p_room_code; return jsonb_build_object('card_label',private.card_label(c.rank,c.suit)); end; $function$
;

CREATE OR REPLACE FUNCTION public.resolve_draw(p_room_code text, p_mode text, p_position integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare dc record; oldc record; ability text; begin if (select phase from public.game_state where room_code=p_room_code)<>'drawn' then raise exception 'No drawn card to resolve'; end if; select c.* into dc from public.game_cards c join public.turn_state t on t.drawn_card_id=c.id where t.room_code=p_room_code and t.drawn_by=auth.uid(); if dc.id is null then raise exception 'No drawn card'; end if; ability:=private.card_ability(dc.rank,dc.suit); if p_mode='discard' then update public.game_cards set zone='discard',owner_user_id=null,position=null,deck_order=null,created_at=now() where id=dc.id; elsif p_mode='replace' then if p_position not between 0 and 3 then raise exception 'Invalid card position'; end if; select * into oldc from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_position; if oldc.id is null then raise exception 'Card not found'; end if; update public.game_cards set zone='discard',owner_user_id=null,position=null,deck_order=null,created_at=now() where id=oldc.id; update public.game_cards set zone='hand',owner_user_id=auth.uid(),position=p_position,deck_order=null where id=dc.id; else raise exception 'Invalid choice'; end if; update public.turn_state set drawn_card_id=null,drawn_by=null,pending_ability=ability,ability_card_rank=dc.rank,ability_card_suit=dc.suit where room_code=p_room_code; perform private.refresh_public_state(p_room_code); if ability='none' then update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); else update public.game_state set phase='ability',updated_at=now() where room_code=p_room_code; end if; return jsonb_build_object('ability',ability); end; $function$
;

CREATE OR REPLACE FUNCTION public.peek_own_card(p_room_code text, p_position integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare c record; begin if (select pending_ability from public.turn_state where room_code=p_room_code)<>'peek_own' then raise exception 'That ability is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'Not your turn'; end if; select * into c from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_position; if c.id is null then raise exception 'Card not found'; end if; update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); return jsonb_build_object('card_label',private.card_label(c.rank,c.suit)); end; $function$
;

CREATE OR REPLACE FUNCTION public.blind_swap(p_room_code text, p_own_position integer, p_target_user_id uuid, p_target_position integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare a uuid; b uuid; begin if (select pending_ability from public.turn_state where room_code=p_room_code)<>'blind_swap' then raise exception 'That ability is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'Not your turn'; end if; if p_target_user_id=auth.uid() then raise exception 'Choose another player'; end if; select id into a from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_own_position; select id into b from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=p_target_user_id and position=p_target_position; if a is null or b is null then raise exception 'Card not found'; end if; update public.game_cards set position=99 where id=a; update public.game_cards set owner_user_id=auth.uid(),position=p_own_position where id=b; update public.game_cards set owner_user_id=p_target_user_id,position=p_target_position where id=a; update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.advance_turn(p_room_code); end; $function$
;

CREATE OR REPLACE FUNCTION public.get_round_scores(p_room_code text)
 RETURNS TABLE(user_id uuid, name text, round_score integer, total_score integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ begin if not private.is_room_member(p_room_code,auth.uid()) then raise exception 'Not in room'; end if; if (select status from public.rooms where code=p_room_code)<>'round_over' then raise exception 'Round is not over'; end if; return query select rp.user_id,rp.name,sum(private.card_points(c.rank,c.suit))::int,rp.total_score from public.room_players rp join public.game_cards c on c.room_code=rp.room_code and c.owner_user_id=rp.user_id and c.zone='hand' where rp.room_code=p_room_code group by rp.user_id,rp.name,rp.total_score,rp.seat order by sum(private.card_points(c.rank,c.suit)),rp.seat; end; $function$
;

CREATE OR REPLACE FUNCTION public.next_round(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ begin if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if; if (select status from public.rooms where code=p_room_code)<>'round_over' then raise exception 'Round is not over'; end if; update public.room_players rp set total_score=rp.total_score+s.score from (select owner_user_id,sum(private.card_points(rank,suit))::int score from public.game_cards where room_code=p_room_code and zone='hand' group by owner_user_id) s where rp.room_code=p_room_code and rp.user_id=s.owner_user_id; perform public.start_game(p_room_code); end; $function$
;

CREATE OR REPLACE FUNCTION public.return_to_lobby(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ begin if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Host only'; end if; delete from public.game_state where room_code=p_room_code; delete from public.game_cards where room_code=p_room_code; delete from public.turn_state where room_code=p_room_code; update public.rooms set status='lobby',cambio_called_by=null,final_turns_remaining=null where code=p_room_code; end; $function$
;

CREATE OR REPLACE FUNCTION public.leave_room(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$ declare h uuid; newh uuid; begin select host_user_id into h from public.rooms where code=p_room_code; if not private.is_room_member(p_room_code,auth.uid()) then return; end if; delete from public.room_players where room_code=p_room_code and user_id=auth.uid(); if not exists(select 1 from public.room_players where room_code=p_room_code) then delete from public.rooms where code=p_room_code; return; end if; if h=auth.uid() then select user_id into newh from public.room_players where room_code=p_room_code order by seat limit 1; update public.rooms set host_user_id=newh where code=p_room_code; end if; end; $function$
;

CREATE OR REPLACE FUNCTION public.peek_other_card(p_room_code text, p_target_user_id uuid, p_position integer, p_swap_own_position integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare c record; ability text;
begin
  select pending_ability into ability from public.turn_state where room_code=p_room_code;
  if ability not in ('peek_other','black_king') then raise exception 'That ability is not active'; end if;
  if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'Not your turn'; end if;
  if p_target_user_id=auth.uid() then raise exception 'Choose another player'; end if;
  select * into c from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=p_target_user_id and position=p_position;
  if c.id is null then raise exception 'Card not found'; end if;
  if ability='peek_other' then
    update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code;
    perform private.advance_turn(p_room_code);
  else
    update public.turn_state set pending_ability='black_king_decide',peeked_target_user_id=p_target_user_id,peeked_target_position=p_position where room_code=p_room_code;
  end if;
  return jsonb_build_object('card_label',private.card_label(c.rank,c.suit),'needs_decision',ability='black_king');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.black_king_decide(p_room_code text, p_swap boolean, p_own_position integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare target_user uuid; target_pos int; a uuid; b uuid;
begin
  if (select pending_ability from public.turn_state where room_code=p_room_code)<>'black_king_decide' then raise exception 'No Black King decision is pending'; end if;
  if (select current_turn_user_id from public.game_state where room_code=p_room_code)<>auth.uid() then raise exception 'Not your turn'; end if;
  select peeked_target_user_id,peeked_target_position into target_user,target_pos from public.turn_state where room_code=p_room_code;
  if p_swap then
    if p_own_position not between 0 and 3 then raise exception 'Choose one of your cards'; end if;
    select id into a from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_own_position;
    select id into b from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=target_user and position=target_pos;
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

create policy rooms_member_select on public.rooms for select to authenticated using (private.is_room_member(code, ( SELECT auth.uid() AS uid)));

create policy room_players_member_select on public.room_players for select to authenticated using (private.is_room_member(room_code, ( SELECT auth.uid() AS uid)));

create policy game_state_member_select on public.game_state for select to authenticated using (private.is_room_member(room_code, ( SELECT auth.uid() AS uid)));

revoke all on public.game_cards, public.turn_state from public,anon,authenticated;

grant select on public.rooms,public.room_players,public.game_state to authenticated;

grant usage on schema private to authenticated;
-- Match the live project's table constraints on fresh installations.
alter table public.rooms add constraint rooms_status_check check(status in ('lobby','playing','round_over'));
alter table public.room_players add constraint room_players_name_check check(char_length(name) between 1 and 18);
alter table public.room_players add constraint room_players_room_code_seat_key unique(room_code,seat);
alter table public.game_cards add constraint game_cards_zone_check check(zone in ('deck','hand','discard'));
alter table public.game_state add constraint game_state_phase_check check(phase in ('waiting','turn','drawn','ability','round_over'));
alter table public.turn_state add constraint turn_state_drawn_card_id_fkey foreign key(drawn_card_id) references public.game_cards(id) on delete set null;
