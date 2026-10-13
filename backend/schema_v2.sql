-- v2 (run after schema.sql): home feed, follows, moments, visitors, open 1:1 chat with anti-spam limit.
create table public.follows(follower uuid references auth.users on delete cascade, followee uuid references auth.users on delete cascade, primary key(follower,followee), check(follower<>followee));
create table public.moments(id bigserial primary key, author uuid not null references auth.users on delete cascade, body text not null check (char_length(body) between 1 and 300), created_at timestamptz default now());
create table public.moment_likes(moment_id bigint references public.moments on delete cascade, user_id uuid references auth.users on delete cascade, primary key(moment_id,user_id));
create table public.visits(visitor uuid references auth.users on delete cascade, visited uuid references auth.users on delete cascade, at timestamptz default now(), primary key(visitor,visited));
alter table public.follows enable row level security; alter table public.moments enable row level security; alter table public.moment_likes enable row level security; alter table public.visits enable row level security;
create policy f_sel on public.follows for select to authenticated using (auth.uid() in (follower,followee));
create policy mo_sel on public.moments for select to authenticated using (not public.is_blocked(auth.uid(),author));
create policy ml_sel on public.moment_likes for select to authenticated using (true);
create policy v_sel on public.visits for select to authenticated using (visited=auth.uid());
revoke insert,update,delete on public.follows,public.moments,public.moment_likes,public.visits from anon,authenticated;
create function public.follow_user(p uuid) returns void language sql security definer set search_path=public as $$ insert into follows values(auth.uid(),p) on conflict do nothing $$;
create function public.unfollow_user(p uuid) returns void language sql security definer set search_path=public as $$ delete from follows where follower=auth.uid() and followee=p $$;
create function public.visit_profile(p uuid) returns void language sql security definer set search_path=public as $$ insert into visits(visitor,visited) values(auth.uid(),p) on conflict(visitor,visited) do update set at=now() $$;
create function public.post_moment(b text) returns bigint language plpgsql security definer set search_path=public as $$
declare i bigint; begin
 if not clean(b) then raise exception 'contact_info_blocked'; end if;
 if (select count(*) from moments where author=auth.uid() and created_at>now()-interval '1 day')>=10 then raise exception 'daily_limit'; end if;
 insert into moments(author,body) values(auth.uid(),trim(b)) returning id into i; return i; end $$;
create function public.like_moment(m bigint) returns void language sql security definer set search_path=public as $$ insert into moment_likes values(m,auth.uid()) on conflict do nothing $$;
-- Home feed (Recommended / Newcomers / Online). Country/city only, never precise location.
create function public.feed(kind text default 'rec', lim int default 30) returns setof public.profiles language sql stable security definer set search_path=public as $$
 select * from profiles p where p.id<>auth.uid() and not is_blocked(auth.uid(),p.id)
 order by case when kind='new' then extract(epoch from p.created_at) end desc nulls last, random() limit lim $$;
-- 1:1 chat without friend requirement; spam limit: max 20 new conversations per day.
create or replace function public.send_dm(p_user uuid,p_body text) returns bigint language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); b text:=trim(p_body); mid bigint;
begin
 if me=p_user or is_blocked(me,p_user) then raise exception 'blocked'; end if;
 if b is null or char_length(b) not between 1 and 1000 then raise exception 'bad_length'; end if;
 if not clean(b) then raise exception 'contact_info_blocked'; end if;
 if not exists(select 1 from dms where (from_id=me and to_id=p_user) or (from_id=p_user and to_id=me)) then
  if (select count(distinct to_id) from dms d where d.from_id=me and d.created_at>now()-interval '1 day'
      and not exists(select 1 from dms r where r.from_id=d.to_id and r.to_id=me))>=20 then raise exception 'daily_limit'; end if;
 end if;
 insert into dms(from_id,to_id,body) values(me,p_user,b) returning id into mid; return mid;
end $$;
