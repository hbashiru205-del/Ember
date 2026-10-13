-- Ember backend (Supabase/Postgres): chat rooms, friends, private chat, coins. Run once in SQL Editor.
create table public.profiles(
 id uuid primary key references auth.users on delete cascade,
 display_name text not null check (char_length(display_name) between 2 and 40),
 dob date not null, country text, language text, bio text check (char_length(bio)<=300), photo_path text,
 created_at timestamptz default now());
create function public.check_adult() returns trigger language plpgsql as $$
begin if new.dob > (current_date - interval '18 years') then raise exception 'must_be_18_or_older'; end if; return new; end $$;
create trigger profiles_adult before insert or update of dob on public.profiles for each row execute function public.check_adult();

create table public.wallets(user_id uuid primary key references auth.users on delete cascade, balance int not null default 0 check (balance>=0));
create table public.token_ledger(id bigserial primary key, user_id uuid not null references auth.users on delete cascade, delta int not null, reason text not null, ref text unique, created_at timestamptz default now());
create function public.make_wallet() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into wallets(user_id) values(new.id) on conflict do nothing; return new; end $$;
create trigger profile_wallet after insert on public.profiles for each row execute function public.make_wallet();

create table public.rooms(id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users on delete cascade, name text not null check (char_length(name) between 3 and 40), topic text, language text, created_at timestamptz default now());
create table public.room_members(room_id uuid references public.rooms on delete cascade, user_id uuid references auth.users on delete cascade, joined_at timestamptz default now(), primary key(room_id,user_id));
create table public.room_bans(room_id uuid references public.rooms on delete cascade, user_id uuid references auth.users on delete cascade, primary key(room_id,user_id));
create table public.room_messages(id bigserial primary key, room_id uuid not null references public.rooms on delete cascade, sender_id uuid not null references auth.users on delete cascade, body text not null, created_at timestamptz default now());
create table public.friend_requests(from_id uuid references auth.users on delete cascade, to_id uuid references auth.users on delete cascade, status text not null default 'pending' check (status in ('pending','accepted')), primary key(from_id,to_id), check(from_id<>to_id));
create table public.dms(id bigserial primary key, from_id uuid not null references auth.users on delete cascade, to_id uuid not null references auth.users on delete cascade, body text not null, created_at timestamptz default now());
create table public.blocks(blocker uuid references auth.users on delete cascade, blocked uuid references auth.users on delete cascade, primary key(blocker,blocked));
create table public.reports(id bigserial primary key, reporter uuid not null references auth.users on delete cascade, reported uuid not null, room_id uuid, reason text not null, details text, created_at timestamptz default now(), status text default 'open');

create function public.is_blocked(a uuid,b uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a)) $$;
create function public.is_member(r uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from room_members where room_id=r and user_id=auth.uid()) $$;
create function public.clean(b text) returns boolean language sql immutable as $$
 select not (b ~* '[a-z0-9._%+-]+\s*(@|\(at\)|\[at\])\s*[a-z0-9.-]+\.[a-z]{2,}' or b ~* '(https?://|www\.|\.com\b|t\.me)' or b ~ '(\d[\s().-]*){7,}' or b ~* '(^|\s)@[a-z0-9_.]{3,}' or b ~* '(whats\s*app|telegram|instagram|snap\s*chat|wechat)') $$;

do $$ declare t text; begin
 foreach t in array array['profiles','wallets','token_ledger','rooms','room_members','room_bans','room_messages','friend_requests','dms','blocks','reports'] loop
  execute format('alter table public.%I enable row level security',t); end loop; end $$;

create policy p_sel on public.profiles for select to authenticated using (id=auth.uid() or not public.is_blocked(auth.uid(),id));
create policy p_ins on public.profiles for insert to authenticated with check (id=auth.uid());
create policy p_upd on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy w_sel on public.wallets for select to authenticated using (user_id=auth.uid());
create policy l_sel on public.token_ledger for select to authenticated using (user_id=auth.uid());
create policy r_sel on public.rooms for select to authenticated using (true);
create policy rm_sel on public.room_members for select to authenticated using (user_id=auth.uid() or public.is_member(room_id));
create policy rmsg_sel on public.room_messages for select to authenticated using (public.is_member(room_id) and not public.is_blocked(auth.uid(),sender_id));
create policy fr_sel on public.friend_requests for select to authenticated using (auth.uid() in (from_id,to_id));
create policy dm_sel on public.dms for select to authenticated using (auth.uid() in (from_id,to_id));
create policy b_all on public.blocks for all to authenticated using (blocker=auth.uid()) with check (blocker=auth.uid());
create policy rep_ins on public.reports for insert to authenticated with check (reporter=auth.uid());

-- Clients cannot write money, rooms, members, messages or friendships directly; only the functions below.
revoke insert,update,delete on public.wallets,public.token_ledger,public.rooms,public.room_members,public.room_bans,public.room_messages,public.friend_requests,public.dms from anon,authenticated;

create function public.create_room(p_name text,p_topic text,p_lang text) returns uuid language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); rid uuid;
begin
 if (select count(*) from rooms where owner=me)>=3 then raise exception 'room_limit'; end if;
 insert into rooms(owner,name,topic,language) values(me,trim(p_name),p_topic,p_lang) returning id into rid;
 insert into room_members(room_id,user_id) values(rid,me); return rid;
end $$;
create function public.join_room(p_room uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from room_bans where room_id=p_room and user_id=auth.uid()) then raise exception 'banned'; end if;
 insert into room_members(room_id,user_id) values(p_room,auth.uid()) on conflict do nothing;
end $$;
create function public.ban_from_room(p_room uuid,p_user uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from rooms where id=p_room and owner=auth.uid()) then raise exception 'not_owner'; end if;
 insert into room_bans values(p_room,p_user) on conflict do nothing; delete from room_members where room_id=p_room and user_id=p_user;
end $$;
create function public.send_room_message(p_room uuid,p_body text) returns bigint language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); b text:=trim(p_body); mid bigint;
begin
 if not is_member(p_room) then raise exception 'not_member'; end if;
 if b is null or char_length(b) not between 1 and 500 then raise exception 'bad_length'; end if;
 if not clean(b) then raise exception 'contact_info_blocked'; end if;
 if (select count(*) from room_messages where sender_id=me and created_at>now()-interval '10 seconds')>=5 then raise exception 'slow_down'; end if;
 insert into room_messages(room_id,sender_id,body) values(p_room,me,b) returning id into mid; return mid;
end $$;
create function public.request_friend(p_user uuid) returns void language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid();
begin
 if me=p_user or is_blocked(me,p_user) then raise exception 'not_allowed'; end if;
 if exists(select 1 from friend_requests where from_id=p_user and to_id=me) then update friend_requests set status='accepted' where from_id=p_user and to_id=me;
 else insert into friend_requests(from_id,to_id) values(me,p_user) on conflict do nothing; end if;
end $$;
create function public.send_dm(p_user uuid,p_body text) returns bigint language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); b text:=trim(p_body); mid bigint;
begin
 if is_blocked(me,p_user) then raise exception 'blocked'; end if;
 if not exists(select 1 from friend_requests where status='accepted' and ((from_id=me and to_id=p_user) or (from_id=p_user and to_id=me))) then raise exception 'not_friends'; end if;
 if b is null or char_length(b) not between 1 and 1000 then raise exception 'bad_length'; end if;
 insert into dms(from_id,to_id,body) values(me,p_user,b) returning id into mid; return mid;
end $$;

create function public.credit_tokens(p_user uuid,p_amount int,p_reason text,p_ref text) returns void language plpgsql security definer set search_path=public as $$
begin
 insert into token_ledger(user_id,delta,reason,ref) values(p_user,p_amount,p_reason,p_ref);
 update wallets set balance=balance+p_amount where user_id=p_user;
exception when unique_violation then null;
end $$;
revoke execute on function public.credit_tokens from public,anon,authenticated;
grant execute on function public.credit_tokens to service_role;
create function public.daily_bonus() returns void language sql security definer set search_path=public as $$
 select public.credit_tokens(auth.uid(),5,'daily','daily:'||auth.uid()||':'||current_date) $$;
create function public.delete_my_account() returns void language sql security definer set search_path=public,auth as $$ delete from auth.users where id=auth.uid() $$;

alter publication supabase_realtime add table public.room_messages, public.dms;
