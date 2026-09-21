-- Public movement metadata only: no card identities, ranks, suits or values.
alter table public.game_state add column swap_events jsonb not null default '[]'::jsonb;
create function private.record_swap(p_room_code text,p_own_position int,p_target_user uuid,p_target_position int)
returns void language plpgsql set search_path='' as $$
declare movement jsonb; recent jsonb;
begin
 select jsonb_build_object('id',gen_random_uuid(),'round',g.round_number,'at',clock_timestamp(),
 'actor_seat',a.seat,'target_seat',b.seat,'own_position',p_own_position,'target_position',p_target_position)
 into movement from public.game_state g join public.room_players a on a.room_code=g.room_code and a.user_id=auth.uid()
 join public.room_players b on b.room_code=g.room_code and b.user_id=p_target_user where g.room_code=p_room_code;
 select coalesce(jsonb_agg(e order by ord),'[]'::jsonb) into recent from (
 select e,ord from public.game_state g cross join lateral jsonb_array_elements(g.swap_events) with ordinality as x(e,ord)
 where g.room_code=p_room_code and (e->>'round')::int=g.round_number order by ord desc limit 15) q;
 update public.game_state set swap_events=recent||jsonb_build_array(movement),updated_at=clock_timestamp() where room_code=p_room_code;
end $$;
revoke all on function private.record_swap(text,int,uuid,int) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.rpc_blind_swap(p_room_code text, p_own_position integer, p_target_user_id uuid, p_target_position integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare a uuid; b uuid; begin perform private.lock_member(p_room_code); if (select status from public.rooms where code=p_room_code) is distinct from 'playing' then raise exception 'Round is not active'; end if; if (select pending_ability from public.turn_state where room_code=p_room_code)is distinct from 'blind_swap' then raise exception 'That ability is not active'; end if; if (select current_turn_user_id from public.game_state where room_code=p_room_code)is distinct from auth.uid() then raise exception 'Not your turn'; end if; if p_target_user_id=auth.uid() then raise exception 'Choose another player'; end if; select id into a from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=auth.uid() and position=p_own_position; select id into b from public.game_cards where room_code=p_room_code and zone='hand' and owner_user_id=p_target_user_id and position=p_target_position; if a is null or b is null then raise exception 'Card not found'; end if; update public.game_cards set position=99 where id=a; update public.game_cards set owner_user_id=auth.uid(),position=p_own_position where id=b; update public.game_cards set owner_user_id=p_target_user_id,position=p_target_position where id=a; update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null where room_code=p_room_code; perform private.record_swap(p_room_code,p_own_position,p_target_user_id,p_target_position); perform private.advance_turn(p_room_code); end; $function$;
CREATE OR REPLACE FUNCTION private.rpc_black_king_decide(p_room_code text, p_swap boolean, p_own_position integer DEFAULT NULL::integer)
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
    perform private.record_swap(p_room_code,p_own_position,target_user,target_pos);
  end if;
  update public.turn_state set pending_ability=null,ability_card_rank=null,ability_card_suit=null,peeked_target_user_id=null,peeked_target_position=null where room_code=p_room_code;
  perform private.advance_turn(p_room_code);
end;
$function$;
