-- New rounds use a standard deck plus two zero-point jokers.
-- Replacing these helpers does not alter cards in rounds already in progress.
create or replace function private.card_label(p_rank text, p_suit text)
returns text language sql immutable set search_path='' as $$
 select case when p_rank='Joker' then 'Joker'
 when p_rank='K' then case when p_suit in ('♥','♦') then 'Red K' else 'Black K' end
 else p_rank||p_suit end;
$$;
create or replace function private.card_points(p_rank text, p_suit text)
returns integer language sql immutable set search_path='' as $$
 select case when p_rank='Joker' then 0
 when p_rank='K' and p_suit in ('♥','♦') then -1
 when p_rank in ('J','Q','K') then 10 when p_rank='A' then 1 else p_rank::int end;
$$;
create or replace function private.build_deck(p_room_code text)
returns void language plpgsql security definer set search_path='' as $$
declare s text; r text; idx integer:=0;
begin
 delete from public.game_cards where room_code=p_room_code;
 foreach s in array array['♠','♥','♦','♣'] loop
  foreach r in array array['A','2','3','4','5','6','7','8','9','10','J','Q','K'] loop
   idx:=idx+1;
   insert into public.game_cards(room_code,zone,rank,suit,deck_order) values(p_room_code,'deck',r,s,idx);
  end loop;
 end loop;
 foreach s in array array['★','☆'] loop
  idx:=idx+1;
  insert into public.game_cards(room_code,zone,rank,suit,deck_order) values(p_room_code,'deck','Joker',s,idx);
 end loop;
 with shuffled as (select id,row_number() over(order by random()) rn from public.game_cards where room_code=p_room_code and zone='deck')
 update public.game_cards c set deck_order=s.rn from shuffled s where c.id=s.id;
end;
$$;
revoke all on function private.card_label(text,text), private.card_points(text,text), private.build_deck(text) from public,anon,authenticated;
