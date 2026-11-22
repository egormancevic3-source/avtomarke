-- АвтоМаркет: запуск схемы Supabase
-- Вставь весь файл в Supabase Dashboard -> SQL Editor -> New query -> Run.

create extension if not exists pgcrypto;

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  seller_name text not null check (char_length(seller_name) between 1 and 80),
  seller_contact text not null check (char_length(seller_contact) between 1 and 120),
  make text not null check (char_length(make) between 1 and 50),
  model text not null check (char_length(model) between 1 and 70),
  year integer not null check (year between 1950 and 2027),
  mileage integer not null check (mileage between 0 and 2000000),
  fuel text not null check (fuel in ('Дизель','Бензин','Гибрид','Электро','Газ')),
  gearbox text not null default 'Не указана',
  price numeric(12,2) not null check (price > 0 and price <= 10000000),
  city text not null default '',
  description text not null default '',
  photos jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected'))
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.listings enable row level security;
alter table public.admin_users enable row level security;

revoke all on public.listings from anon, authenticated;
grant select, insert on public.listings to anon, authenticated;
grant select, update, delete on public.listings to authenticated;
revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to authenticated;

drop policy if exists "Public can view approved listings" on public.listings;
create policy "Public can view approved listings" on public.listings
for select to anon, authenticated using (status = 'approved' or exists (
  select 1 from public.admin_users a where a.user_id = auth.uid()
));

drop policy if exists "Anyone can submit pending listings" on public.listings;
create policy "Anyone can submit pending listings" on public.listings
for insert to anon, authenticated with check (status = 'pending');

drop policy if exists "Admins can update listings" on public.listings;
create policy "Admins can update listings" on public.listings
for update to authenticated using (exists (
  select 1 from public.admin_users a where a.user_id = auth.uid()
)) with check (exists (
  select 1 from public.admin_users a where a.user_id = auth.uid()
));

drop policy if exists "Admins can delete listings" on public.listings;
create policy "Admins can delete listings" on public.listings
for delete to authenticated using (exists (
  select 1 from public.admin_users a where a.user_id = auth.uid()
));

drop policy if exists "Admins can view admin membership" on public.admin_users;
create policy "Admins can view admin membership" on public.admin_users
for select to authenticated using (user_id = auth.uid());

-- Public image bucket. Anonymous visitors may upload images only because the listing form
-- must support submissions without an account. Apply a size limit in Storage settings too.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('car-photos', 'car-photos', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Public can upload car photos" on storage.objects;
create policy "Public can upload car photos" on storage.objects
for insert to anon, authenticated with check (bucket_id = 'car-photos');

drop policy if exists "Anyone can view car photos" on storage.objects;
create policy "Anyone can view car photos" on storage.objects
for select to anon, authenticated using (bucket_id = 'car-photos');

drop policy if exists "Admins can delete car photos" on storage.objects;
create policy "Admins can delete car photos" on storage.objects
for delete to authenticated using (
  bucket_id = 'car-photos' and exists (
    select 1 from public.admin_users a where a.user_id = auth.uid()
  )
);

-- After creating your own admin user in Authentication, run the following separately
-- after replacing UUID with that user's actual ID:
-- insert into public.admin_users (user_id) values ('YOUR-AUTH-USER-UUID');
