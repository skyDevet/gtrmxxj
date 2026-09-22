-- Run this in Supabase → SQL Editor

create extension if not exists "pgcrypto";

-- Pins: metadata + Drive file reference
create table if not exists pins (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  user_email text,
  user_name text,
  user_picture text,
  drive_file_id text not null,
  drive_url text not null,
  drive_view_url text,
  title text,
  description text,
  category text,
  class text,
  image_width int,
  image_height int,
  features jsonb,
  pose jsonb,
  likes int default 0,
  saved boolean default false,
  comments jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

create index if not exists pins_user_id_idx on pins(user_id);
create index if not exists pins_category_idx on pins(category);
create index if not exists pins_created_at_idx on pins(created_at desc);

-- User tokens: encrypted refresh tokens per user
create table if not exists user_tokens (
  user_id text primary key,
  email text,
  name text,
  picture text,
  refresh_token_encrypted text not null,
  access_token_encrypted text,
  access_token_expires_at timestamptz,
  scope text,
  updated_at timestamptz default now()
);

-- RLS: server uses service_role so it bypasses these, but enable for safety
alter table pins enable row level security;
alter table user_tokens enable row level security;

-- Drop existing policies if re-running
drop policy if exists "public read pins" on pins;
create policy "public read pins" on pins for select using (true);
