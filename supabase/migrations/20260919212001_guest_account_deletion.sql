-- Adds self-service deletion without changing existing rooms until a player requests it.
begin;
create or replace function private.require_current_user() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from auth.users where id=auth.uid() for key share;
 if not found then raise exception 'Your guest session has ended. Start a new game.'; end if;
end $$;
revoke all on function private.require_current_user() from public,anon,authenticated;
-- Prevent still-unexpired tokens from creating/rejoining rooms after deletion.
do $$declare f text;def text;begin
 foreach f in array array['private.rpc_create_room(text)','private.rpc_join_room(text,text)'] loop
 def:=pg_get_functiondef(f::regprocedure);
 def:=regexp_replace(def,'\mbegin\M','begin perform private.require_current_user();','i');
 execute def;
 end loop;
end $$;
create or replace function private.rpc_delete_guest_account() returns void
language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid();r record;p public.room_players;replacement uuid;next_host uuid;old_seat int;
begin
 if who is null then raise exception 'Sign in first'; end if;
 perform 1 from auth.users where id=who and is_anonymous=true for update;
 if not found then raise exception 'Guest account not found'; end if;
 -- Lock in a stable order, shared with normal game actions.
 for r in select rooms.code from public.rooms rooms where exists(select 1 from public.room_players rp where rp.room_code=rooms.code and rp.user_id=who) order by rooms.code for update loop
 select * into p from public.room_players where room_code=r.code and user_id=who;
 select user_id into next_host from public.room_players where room_code=r.code and user_id<>who and not is_bot order by seat limit 1;
 if next_host is null then delete from public.rooms where code=r.code;continue;end if;
 replacement:=gen_random_uuid();old_seat:=p.seat;
 -- New, unlinkable bot identity keeps friends' pending powers/turns valid.
 insert into public.room_players(room_code,user_id,name,seat,total_score,first_turn_started,initial_ready,is_bot,bot_difficulty)
 values(r.code,replacement,'Clover · Bot',1000+old_seat,p.total_score,p.first_turn_started,true,true,'medium');
 update public.game_cards set owner_user_id=replacement where room_code=r.code and owner_user_id=who;
 update public.game_state set current_turn_user_id=replacement where room_code=r.code and current_turn_user_id=who;
 update public.turn_state set drawn_by=case when drawn_by=who then replacement else drawn_by end,peeked_target_user_id=case when peeked_target_user_id=who then replacement else peeked_target_user_id end where room_code=r.code;
 update public.rooms set host_user_id=case when host_user_id=who then next_host else host_user_id end,cambio_called_by=case when cambio_called_by=who then replacement else cambio_called_by end where code=r.code;
 update public.round_scores set user_id=replacement,name='Clover · Bot' where room_code=r.code and user_id=who;
 delete from public.room_players where room_code=r.code and user_id=who;
 update public.room_players set seat=old_seat where room_code=r.code and user_id=replacement;
 insert into private.bot_state values(r.code,replacement,0);
 -- Only knowledge available to this seat under the rules is transferred.
 if not p.first_turn_started then
 perform private.remember_card(r.code,replacement,id) from public.game_cards where room_code=r.code and owner_user_id=replacement and zone='hand' and position in(2,3);
 end if;
 perform private.remember_card(r.code,replacement,id) from public.game_cards where room_code=r.code and zone='discard';
 perform private.remember_card(r.code,replacement,drawn_card_id) from public.turn_state where room_code=r.code and drawn_by=replacement;
 perform private.remember_card(r.code,replacement,peeked_card_id) from public.turn_state where room_code=r.code and (select current_turn_user_id from public.game_state where room_code=r.code)=replacement;
 if (select phase from public.game_state where room_code=r.code)='waiting' and not exists(select 1 from public.room_players where room_code=r.code and not initial_ready) then
 update public.game_state set phase='turn',updated_at=now() where room_code=r.code;
 update public.room_players set first_turn_started=true where room_code=r.code and user_id=(select current_turn_user_id from public.game_state where room_code=r.code);
 end if;
 end loop;
 delete from public.round_scores where user_id=who;
 delete from auth.users where id=who;
end $$;
create or replace function public.delete_guest_account() returns void language sql security invoker set search_path='' as $$select private.rpc_delete_guest_account()$$;
revoke all on function private.rpc_delete_guest_account(),public.delete_guest_account() from public,anon;
grant execute on function private.rpc_delete_guest_account(),public.delete_guest_account() to authenticated;
notify pgrst,'reload schema';
commit;
