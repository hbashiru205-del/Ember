-- Ember backend for Supabase (Postgres). Paste into SQL Editor and run once.
create table public.profiles(
 id uuid primary key references auth.users on delete cascade,
 display_name text not null check (char_length(display_name) between 2 and 40),
 dob date not null, gender text, looking_for text, country text,
 bio text check (char_length(bio)<=500), photo_path text,
 created_at timestamptz default now());

create function public.check_adult() returns trigger language plpgsql as $$
begin
 if new.dob > (current_date - interval '18 years') then raise exception 'must_be_18_or_older'; end if;
 return new;
end $$;
create trigger profiles_adult before insert or update of dob on public.profiles
 for each row execute function public.check_adult();

create table public.wallets(user_id uuid primary key references auth.users on delete cascade, balance int not null default 0 check (balance>=0));
create table public.token_ledger(id bigserial primary key, user_id uuid not null references auth.users on delete cascade, delta int not null, reason text not null, ref text unique, created_at timestamptz default now());
create function public.make_wallet() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into wallets(user_id) values(new.id) on conflict do nothing; return new; end $$;
create trigger profile_wallet after insert on public.profiles for each row execute function public.make_wallet();

create table public.likes(from_id uuid references auth.users on delete cascade, to_id uuid references auth.users on delete cascade, created_at timestamptz default now(), primary key(from_id,to_id), check(from_id<>to_id));
create table public.matches(id uuid primary key default gen_random_uuid(), user_a uuid not null references auth.users on delete cascade, user_b uuid not null references auth.users on delete cascade, created_at timestamptz default now(), unique(user_a,user_b), check(user_a<user_b));
create table public.messages(id bigserial primary key, match_id uuid not null references public.matches on delete cascade, sender_id uuid not null references auth.users on delete cascade, body text not null, created_at timestamptz default now());
create table public.blocks(blocker uuid references auth.users on delete cascade, blocked uuid references auth.users on delete cascade, primary key(blocker,blocked));
create table public.reports(id bigserial primary key, reporter uuid not null references auth.users on delete cascade, reported uuid not null, reason text not null, details text, created_at timestamptz default now(), status text default 'open');

create function public.is_blocked(a uuid,b uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a)) $$;

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.token_ledger enable row level security;
alter table public.likes enable row level security;
alter table public.matches enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

create policy p_sel on public.profiles for select to authenticated using (id=auth.uid() or not public.is_blocked(auth.uid(),id));
create policy p_ins on public.profiles for insert to authenticated with check (id=auth.uid());
create policy p_upd on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy w_sel on public.wallets for select to authenticated using (user_id=auth.uid());
create policy l_sel on public.token_ledger for select to authenticated using (user_id=auth.uid());
create policy lk_sel on public.likes for select to authenticated using (from_id=auth.uid());
create policy m_sel on public.matches for select to authenticated using (auth.uid() in (user_a,user_b));
create policy ms_sel on public.messages for select to authenticated using (exists(select 1 from matches m where m.id=match_id and auth.uid() in (m.user_a,m.user_b)));
create policy b_all on public.blocks for all to authenticated using (blocker=auth.uid()) with check (blocker=auth.uid());
create policy r_ins on public.reports for insert to authenticated with check (reporter=auth.uid());

-- No direct writes to money/matches/messages; only the functions below can write them.
revoke insert,update,delete on public.wallets,public.token_ledger,public.likes,public.matches,public.messages from anon,authenticated;

create function public.like_user(target uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); matched boolean:=false;
begin
 if me is null or me=target or is_blocked(me,target) then raise exception 'not_allowed'; end if;
 insert into likes(from_id,to_id) values(me,target) on conflict do nothing;
 if exists(select 1 from likes where from_id=target and to_id=me) then
  insert into matches(user_a,user_b) values(least(me,target),greatest(me,target)) on conflict do nothing;
  matched:=true;
 end if;
 return matched;
end $$;

create function public.discover(lim int default 20) returns setof public.profiles language sql stable security definer set search_path=public as $$
 select p.* from profiles p where p.id<>auth.uid()
 and not is_blocked(auth.uid(),p.id)
 and not exists(select 1 from likes l where l.from_id=auth.uid() and l.to_id=p.id)
 order by random() limit lim $$;

create function public.send_message(p_match uuid, p_body text) returns bigint language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); m matches; other uuid; sent int; mid bigint; b text:=trim(p_body);
begin
 select * into m from matches where id=p_match and me in (user_a,user_b);
 if not found then raise exception 'not_in_match'; end if;
 other:=case when m.user_a=me then m.user_b else m.user_a end;
 if is_blocked(me,other) then raise exception 'blocked'; end if;
 if b is null or char_length(b) not between 1 and 1000 then raise exception 'bad_length'; end if;
 if b ~* '[a-z0-9._%+-]+\s*(@|\(at\)|\[at\])\s*[a-z0-9.-]+\.[a-z]{2,}'
    or b ~* '(https?://|www\.|\.com\b|\.me/|t\.me)'
    or b ~ '(\d[\s().-]*){7,}'
    or b ~* '(^|\s)@[a-z0-9_.]{3,}'
    or b ~* '(whats\s*app|telegram|instagram|snap\s*chat|signal|wechat|discord|\big\b)'
 then raise exception 'contact_info_blocked'; end if;
 select count(*) into sent from messages where match_id=p_match and sender_id=me;
 if sent>=15 then
  update wallets set balance=balance-1 where user_id=me and balance>=1;
  if not found then raise exception 'no_tokens'; end if;
  insert into token_ledger(user_id,delta,reason) values(me,-1,'message');
 end if;
 insert into messages(match_id,sender_id,body) values(p_match,me,b) returning id into mid;
 return mid;
end $$;

-- Called ONLY by your payment/ad webhook with the service_role key. Idempotent via ref.
create function public.credit_tokens(p_user uuid,p_amount int,p_reason text,p_ref text) returns void language plpgsql security definer set search_path=public as $$
begin
 insert into token_ledger(user_id,delta,reason,ref) values(p_user,p_amount,p_reason,p_ref);
 update wallets set balance=balance+p_amount where user_id=p_user;
exception when unique_violation then null;
end $$;
revoke execute on function public.credit_tokens from public,anon,authenticated;
grant execute on function public.credit_tokens to service_role;

create function public.delete_my_account() returns void language sql security definer set search_path=public,auth as $$
 delete from auth.users where id=auth.uid() $$;

alter publication supabase_realtime add table public.messages;
