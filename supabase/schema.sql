-- DataBee initial schema for a NEW Supabase project.
-- Run this in Supabase Dashboard > SQL Editor > New query.
-- Safe client access is controlled by RLS. Never disable RLS for production.

create extension if not exists pgcrypto;

create table if not exists public.products (
  id text primary key,
  name text not null,
  brand text not null default 'Generic',
  category text not null default 'Other',
  price numeric(12,2) not null default 0 check (price >= 0),
  description text not null default '',
  stock integer not null default 0 check (stock >= 0),
  image_url text not null default '',
  specs jsonb not null default '{}'::jsonb,
  featured boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists public.delivery_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipient_name text not null,
  phone text not null,
  street text not null,
  barangay text not null,
  city text not null,
  province text not null,
  postal_code text not null,
  is_default boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  product_id text references public.products(id) on delete set null,
  product_name text not null,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  quantity integer not null default 1 check (quantity > 0),
  status text not null default 'PENDING',
  external_id text unique,
  created_at timestamptz not null default now()
);

alter table public.products enable row level security;
alter table public.favorites enable row level security;
alter table public.delivery_addresses enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Active products are visible to everyone" on public.products;
create policy "Active products are visible to everyone"
  on public.products for select to anon, authenticated
  using (is_active = true);

drop policy if exists "Users can read their own favorites" on public.favorites;
create policy "Users can read their own favorites"
  on public.favorites for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "Users can add their own favorites" on public.favorites;
create policy "Users can add their own favorites"
  on public.favorites for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "Users can remove their own favorites" on public.favorites;
create policy "Users can remove their own favorites"
  on public.favorites for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can read their own delivery addresses" on public.delivery_addresses;
create policy "Users can read their own delivery addresses"
  on public.delivery_addresses for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "Users can create their own delivery addresses" on public.delivery_addresses;
create policy "Users can create their own delivery addresses"
  on public.delivery_addresses for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "Users can update their own delivery addresses" on public.delivery_addresses;
create policy "Users can update their own delivery addresses"
  on public.delivery_addresses for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete their own delivery addresses" on public.delivery_addresses;
create policy "Users can delete their own delivery addresses"
  on public.delivery_addresses for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can read their own orders" on public.orders;
create policy "Users can read their own orders"
  on public.orders for select to authenticated
  using (auth.uid() = user_id);

-- Add products from your approved catalog after running this schema.
-- image_url should be a direct, stable image URL for the exact product model.
