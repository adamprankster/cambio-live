begin;
lock table public.rooms in access exclusive mode;
alter table public.room_players add column if not exists is_bot boolean not null default false;
alter table public.room_players add column if not exists bot_difficulty text check(bot_difficulty in ('easy','medium','hard'));
alter table public.rooms add column if not exists bot_next_action_at timestamptz not null default now();
create table private.bot_memory (
 room_code text not null,bot_id uuid not null,card_id uuid not null references public.game_cards(id) on delete cascade,
 rank text not null,suit text not null,primary key(bot_id,card_id),
 foreign key(room_code,bot_id) references public.room_players(room_code,user_id) on delete cascade
);
create table private.bot_state (
 room_code text not null,bot_id uuid not null,turns int not null default 0,
 primary key(room_code,bot_id),foreign key(room_code,bot_id) references public.room_players(room_code,user_id) on delete cascade
);
alter table private.bot_memory enable row level security;
alter table private.bot_state enable row level security;
revoke all on private.bot_memory,private.bot_state from public,anon,authenticated;

create function private.remember_card(p_room text,p_bot uuid,p_card uuid) returns void language sql security definer set search_path='' as $$
 insert into private.bot_memory(room_code,bot_id,card_id,rank,suit)
 select p_room,p_bot,id,rank,suit from public.game_cards where id=p_card and room_code=p_room
 on conflict(bot_id,card_id) do update set rank=excluded.rank,suit=excluded.suit;
$$;
-- Public discards can be remembered. Shuffling breaks the link to card identity.
create function private.observe_bot_cards() returns trigger language plpgsql security definer set search_path='' as $$
declare b record;
begin
 if new.zone='deck' then delete from private.bot_memory where card_id=new.id;
 elsif new.zone='discard' then
 update public.rooms set bot_next_action_at=clock_timestamp()+interval '2.5 seconds' where code=new.room_code;
 for b in select user_id from public.room_players where room_code=new.room_code and is_bot loop
 perform private.remember_card(new.room_code,b.user_id,new.id);
 end loop;
 end if;
 return new;
end $$;
create trigger bot_observe_card after insert or update of zone on public.game_cards for each row execute function private.observe_bot_cards();
create function private.prepare_bots(p_room text) returns void language plpgsql security definer set search_path='' as $$
declare b record;c record;
begin
 delete from private.bot_memory where room_code=p_room;
 delete from private.bot_state where room_code=p_room;
 for b in select user_id from public.room_players where room_code=p_room and is_bot loop
 insert into private.bot_state values(p_room,b.user_id,0);
 for c in select id from public.game_cards where room_code=p_room and ((zone='hand' and owner_user_id=b.user_id and position in(2,3)) or zone='discard') loop
 perform private.remember_card(p_room,b.user_id,c.id);
 end loop;
 update public.room_players set initial_ready=true where room_code=p_room and user_id=b.user_id;
 end loop;
 update public.rooms set bot_next_action_at=clock_timestamp()+interval '1.2 seconds' where code=p_room;
end $$;
create function private.rpc_add_bot(p_room_code text,p_difficulty text) returns uuid language plpgsql security definer set search_path='' as $$
declare bot uuid:=gen_random_uuid();seatn int;label text;
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Only the host can add bots'; end if;
 if (select status from public.rooms where code=p_room_code)<>'lobby' then raise exception 'Add bots in the lobby'; end if;
 if p_difficulty is null or p_difficulty not in('easy','medium','hard') then raise exception 'Choose a difficulty'; end if;
 if (select count(*) from public.room_players where room_code=p_room_code)>=6 then raise exception 'The table is full'; end if;
 select coalesce(max(seat),-1)+1 into seatn from public.room_players where room_code=p_room_code;
 label:=(array['Clover','Pip','Rook','Fern','Ace','Nova'])[1+(seatn%6)];
 insert into public.room_players(room_code,user_id,name,seat,is_bot,bot_difficulty) values(p_room_code,bot,label||' · Bot',seatn,true,p_difficulty);
 return bot;
end $$;
create function private.rpc_remove_bot(p_room_code text,p_bot_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.lock_member(p_room_code);
 if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Only the host can remove bots'; end if;
 if (select status from public.rooms where code=p_room_code)<>'lobby' then raise exception 'Remove bots in the lobby'; end if;
 delete from public.room_players where room_code=p_room_code and user_id=p_bot_id and is_bot;
 if not found then raise exception 'Bot not found'; end if;
end $$;

-- All decisions below use remembered values, never the ranks of hidden cards.
-- Only draw/peek execution may add private knowledge, after the normal RPC allows it.
create function private.rpc_tick_bots(p_room_code text) returns boolean language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid();g public.game_state;b public.room_players;t public.turn_state;
 topc public.game_cards;own record;target record;dc public.game_cards;candidate record;
 estimate numeric;opponent_estimate numeric;nturn int;did boolean:=false;draw_source text;memory_value int;
begin
 perform private.lock_member(p_room_code);
 if exists(select 1 from public.room_players where room_code=p_room_code and user_id=caller and is_bot) then raise exception 'A human player must request bot moves'; end if;
 if (select status from public.rooms where code=p_room_code)<>'playing' then return false; end if;
 if (select bot_next_action_at from public.rooms where code=p_room_code)>clock_timestamp() then return false; end if;
 update public.rooms set bot_next_action_at=clock_timestamp()+interval '1.2 seconds' where code=p_room_code;
 select * into g from public.game_state where room_code=p_room_code;
 if g.phase='waiting' then return false; end if;
 -- A bot may slam only a remembered match; it cannot probe hidden ranks.
 select * into topc from public.game_cards c where c.room_code=p_room_code and zone='discard'
 and not exists(select 1 from public.turn_state ts where ts.room_code=p_room_code and ts.drawn_card_id=c.id) order by discard_order desc nulls last limit 1;
 if topc.id is not null then
 select p.user_id,c.position,p.bot_difficulty into candidate from public.room_players p
 join private.bot_memory m on m.room_code=p.room_code and m.bot_id=p.user_id
 join public.game_cards c on c.id=m.card_id and c.zone='hand' and c.owner_user_id=p.user_id
 where p.room_code=p_room_code and p.is_bot and m.rank=topc.rank
 and random()<case p.bot_difficulty when 'easy' then .2 when 'medium' then .6 else .95 end
 order by random() limit 1;
 if candidate.user_id is not null then
 perform set_config('request.jwt.claim.sub',candidate.user_id::text,true);
 perform public.slam_card(p_room_code,candidate.position,topc.discard_order);did:=true;
 perform set_config('request.jwt.claim.sub',caller::text,true);return did;
 end if;
 end if;
 select * into b from public.room_players where room_code=p_room_code and user_id=g.current_turn_user_id and is_bot;
 if b.user_id is null then return false; end if;
 perform set_config('request.jwt.claim.sub',b.user_id::text,true);
 select * into t from public.turn_state where room_code=p_room_code;
 if g.phase='turn' then
 update private.bot_state set turns=turns+1 where room_code=p_room_code and bot_id=b.user_id returning turns into nturn;
 if b.bot_difficulty<>'hard' then delete from private.bot_memory where room_code=p_room_code and bot_id=b.user_id and random()<case b.bot_difficulty when 'easy' then .25 else .07 end;end if;
 select coalesce(sum(coalesce(private.card_points(m.rank,m.suit),6)),0) into estimate from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=b.user_id;
 select min(score) into opponent_estimate from (select p.user_id,coalesce(sum(coalesce(private.card_points(m.rank,m.suit),6)),0) score from public.room_players p left join public.game_cards c on c.room_code=p.room_code and c.owner_user_id=p.user_id and c.zone='hand' left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where p.room_code=p_room_code and p.user_id<>b.user_id group by p.user_id) q;
 if (select cambio_called_by from public.rooms where code=p_room_code) is null and
 (estimate=0 or nturn>=case b.bot_difficulty when 'easy' then 14 when 'medium' then 12 else 10 end or (nturn>=2 and estimate<=case b.bot_difficulty when 'easy' then 10 when 'medium' then 8 else least(10,opponent_estimate-2) end)) then
 perform public.call_cambio(p_room_code);
 else
 select c.position,coalesce(private.card_points(m.rank,m.suit),6) value into own from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=b.user_id order by coalesce(private.card_points(m.rank,m.suit),6) desc,c.position limit 1;
 draw_source:='deck';
 perform public.draw_from(p_room_code,draw_source);
 select * into dc from public.game_cards where id=(select drawn_card_id from public.turn_state where room_code=p_room_code);
 perform private.remember_card(p_room_code,b.user_id,dc.id);
 end if;
 elsif g.phase='drawn' then
 select * into dc from public.game_cards where id=t.drawn_card_id and t.drawn_by=b.user_id;
 select c.position,coalesce(private.card_points(m.rank,m.suit),6) value into own from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=b.user_id order by coalesce(private.card_points(m.rank,m.suit),6) desc,c.position limit 1;
 if own.position is not null and private.card_points(dc.rank,dc.suit)<own.value then perform public.resolve_draw(p_room_code,'replace',own.position);
 else perform public.resolve_draw(p_room_code,'discard',null);end if;
 elsif g.phase='ability' then
 select c.id,c.position,coalesce(private.card_points(m.rank,m.suit),6) value into own from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=b.user_id order by coalesce(private.card_points(m.rank,m.suit),6) desc,c.position limit 1;
 if t.pending_ability='peek_own' then
 select c.id,c.position into target from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id=b.user_id order by (m.card_id is null) desc,random() limit 1;
 if target.id is null then perform public.skip_ability(p_room_code);else perform public.peek_own_card(p_room_code,target.position);perform private.remember_card(p_room_code,b.user_id,target.id);end if;
 elsif t.pending_ability in('peek_other','black_king') then
 select c.id,c.position,c.owner_user_id into target from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id<>b.user_id order by (m.card_id is null) desc,random() limit 1;
 if target.id is null then perform public.skip_ability(p_room_code);else perform public.peek_other_card(p_room_code,target.owner_user_id,target.position,null);perform private.remember_card(p_room_code,b.user_id,target.id);end if;
 elsif t.pending_ability='blind_swap' then
 select c.id,c.position,c.owner_user_id,coalesce(private.card_points(m.rank,m.suit),6) value into target from public.game_cards c left join private.bot_memory m on m.card_id=c.id and m.bot_id=b.user_id where c.room_code=p_room_code and c.zone='hand' and c.owner_user_id<>b.user_id order by coalesce(private.card_points(m.rank,m.suit),6),random() limit 1;
 if own.position is null or target.id is null or target.value>=own.value then perform public.skip_ability(p_room_code);else perform public.blind_swap(p_room_code,own.position,target.owner_user_id,target.position);end if;
 elsif t.pending_ability='black_king_decide' then
 select private.card_points(m.rank,m.suit) into memory_value from private.bot_memory m join public.game_cards c on c.id=m.card_id and c.zone='hand' and c.owner_user_id=t.peeked_target_user_id and c.position=t.peeked_target_position where m.bot_id=b.user_id and m.card_id=t.peeked_card_id;
 perform public.black_king_decide(p_room_code,own.position is not null and memory_value is not null and memory_value<own.value,own.position);
 else perform public.skip_ability(p_room_code);end if;
 end if;
 perform set_config('request.jwt.claim.sub',caller::text,true);return true;
end $$;
create function public.add_bot(p_room_code text,p_difficulty text default 'medium') returns uuid language sql security invoker set search_path='' as $$select private.rpc_add_bot(p_room_code,p_difficulty)$$;
create function public.remove_bot(p_room_code text,p_bot_id uuid) returns void language sql security invoker set search_path='' as $$select private.rpc_remove_bot(p_room_code,p_bot_id)$$;
create function public.tick_bots(p_room_code text) returns boolean language sql security invoker set search_path='' as $$select private.rpc_tick_bots(p_room_code)$$;

CREATE OR REPLACE FUNCTION private.rpc_start_game(p_room_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare p record; c record; topc record; first_user uuid; current_round int; begin perform private.lock_member(p_room_code); if not private.is_room_host(p_room_code,auth.uid()) then raise exception 'Only the host can start'; end if; if (select count(*) from public.room_players where room_code=p_room_code)<2 then raise exception 'Need at least 2 players'; end if; select coalesce(round_number,0)+1 into current_round from public.game_state where room_code=p_room_code; if current_round is null then current_round:=1; end if; if (select game_over from public.rooms where code=p_room_code) then raise exception 'The match is over. Start a new match.'; end if; if (select status from public.rooms where code=p_room_code)='playing' then raise exception 'Round already in progress'; end if; perform private.build_deck(p_room_code); for p in select * from public.room_players where room_code=p_room_code order by seat loop for i in 0..3 loop select * into c from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='hand',owner_user_id=p.user_id,position=i,deck_order=null where id=c.id; end loop; end loop; select * into topc from public.game_cards where room_code=p_room_code and zone='deck' order by deck_order limit 1; update public.game_cards set zone='discard',deck_order=null,created_at=clock_timestamp(),discard_order=nextval('private.discard_sequence') where id=topc.id; select user_id into first_user from public.room_players where room_code=p_room_code order by seat limit 1; insert into public.game_state(room_code,current_turn_user_id,deck_count,discard_top_label,phase,round_number) values(p_room_code,first_user,(select count(*) from public.game_cards where room_code=p_room_code and zone='deck'),private.card_label(topc.rank,topc.suit),'waiting',current_round) on conflict(room_code) do update set current_turn_user_id=excluded.current_turn_user_id,deck_count=excluded.deck_count,discard_top_label=excluded.discard_top_label,phase='waiting',round_number=excluded.round_number,updated_at=now(); insert into public.turn_state(room_code) values(p_room_code) on conflict(room_code) do update set drawn_card_id=null,drawn_by=null,pending_ability=null,ability_card_rank=null,ability_card_suit=null; update public.room_players set first_turn_started=false,initial_ready=false where room_code=p_room_code; update public.turn_state set peeked_card_id=null,peeked_label=null,peeked_target_user_id=null,peeked_target_position=null,draw_source=null where room_code=p_room_code; update public.rooms set status='playing',cambio_called_by=null,final_turns_remaining=null where code=p_room_code; perform private.prepare_bots(p_room_code); end; $function$
;
create or replace function private.rpc_leave_room(p_room_code text) returns void
language plpgsql security definer set search_path='' as $$
declare h uuid;
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code)='playing' then raise exception 'A round is in progress. Close the page to disconnect and rejoin later.'; end if;
 select host_user_id into h from public.rooms where code=p_room_code;
 delete from public.room_players where room_code=p_room_code and user_id=auth.uid();
 if not exists(select 1 from public.room_players where room_code=p_room_code and not is_bot) then delete from public.rooms where code=p_room_code;
 elsif h=auth.uid() then update public.rooms set host_user_id=(select user_id from public.room_players where room_code=p_room_code and not is_bot order by seat limit 1) where code=p_room_code; end if;
end $$;
revoke all on function private.remember_card(text,uuid,uuid),private.observe_bot_cards(),private.prepare_bots(text) from public,anon,authenticated;
revoke all on function private.rpc_add_bot(text,text),private.rpc_remove_bot(text,uuid),private.rpc_tick_bots(text),public.add_bot(text,text),public.remove_bot(text,uuid),public.tick_bots(text) from public,anon;
grant execute on function private.rpc_add_bot(text,text),private.rpc_remove_bot(text,uuid),private.rpc_tick_bots(text),public.add_bot(text,text),public.remove_bot(text,uuid),public.tick_bots(text) to authenticated;
notify pgrst,'reload schema';
create or replace function private.rpc_draw_from(p_room_code text,p_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.game_cards; picked uuid;
begin
 perform private.lock_member(p_room_code);
 if (select status from public.rooms where code=p_room_code) is distinct from 'playing'
 or (select phase from public.game_state where room_code=p_room_code) is distinct from 'turn'
 or (select current_turn_user_id from public.game_state where room_code=p_room_code) is distinct from auth.uid() then raise exception 'You cannot draw now'; end if;
 if p_source is distinct from 'deck' then raise exception 'Draw from the deck. The discard pile is for slamming.'; end if;
 picked:=private.take_deck(p_room_code);
 if picked is null then perform private.advance_turn(p_room_code);return jsonb_build_object('passed',true);end if;
 select * into c from public.game_cards where id=picked;
 update public.turn_state set drawn_card_id=picked,drawn_by=auth.uid(),draw_source=p_source where room_code=p_room_code;
 update public.game_state set phase='drawn' where room_code=p_room_code;
 perform private.refresh_public_state(p_room_code);
 return jsonb_build_object('card_label',private.card_label(c.rank,c.suit));
end $$;

commit;
