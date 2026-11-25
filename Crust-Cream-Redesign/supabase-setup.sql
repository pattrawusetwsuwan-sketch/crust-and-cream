-- Crust&Cream database setup for Supabase
-- Run this entire file in Supabase Dashboard > SQL Editor > New query.

create extension if not exists pgcrypto;
create sequence if not exists public.order_number_seq start 1043;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  status text not null default 'ready' check (status in ('ready','preorder')),
  image_url text not null default 'assets/tart-assortment.webp',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.shop_settings (
  id integer primary key default 1 check (id = 1),
  brand_name text not null default 'Crust&Cream',
  announcement text not null default 'อบสดใหม่จากเตาทุกวัน • สั่งล่วงหน้า (Pre-order) 1 วัน หรือเลือกเมนูพร้อมส่งวันนี้',
  hero_title text not null default 'ความสุขชิ้นเล็ก อบสดใหม่จากใจ',
  hero_desc text not null default 'ทาร์ตผลไม้โฮมเมด แป้งกรอบหอมเนย ครีมคัสตาร์ดวานิลลาหวานน้อย และผลไม้สดตามฤดูกาล',
  hours text not null default 'เปิดทุกวัน 09:00 – 18:30 น.',
  address text not null default 'รับหน้าร้าน / ส่งแมสเซ็นเจอร์',
  contact text not null default 'Instagram: @crustandcream'
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique default ('CC-' || nextval('public.order_number_seq')::text),
  customer_name text not null check (char_length(customer_name) between 2 and 120),
  phone text not null check (char_length(phone) between 9 and 20),
  order_type text not null default 'พร้อมส่ง' check (order_type in ('พร้อมส่ง','Pre-order')),
  pickup_date date not null,
  note text not null default '',
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0),
  total numeric(10,2) not null check (total > 0),
  status text not null default 'รอยืนยัน' check (status in ('รอยืนยัน','กำลังอบ','พร้อมรับ/จัดส่ง','เสร็จสิ้น','ยกเลิก')),
  created_at timestamptz not null default now()
);

-- Admin allow-list. Add the Auth user's UUID here after creating the account.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_store_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

alter table public.products enable row level security;
alter table public.shop_settings enable row level security;
alter table public.orders enable row level security;
alter table public.admin_users enable row level security;

-- Public can view active products; only allow-listed admins can manage products.
drop policy if exists "Public can view active products" on public.products;
create policy "Public can view active products" on public.products for select to anon, authenticated using (is_active = true or public.is_store_admin());
drop policy if exists "Admins manage products" on public.products;
create policy "Admins manage products" on public.products for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

-- Store details are public; editing is admin-only.
drop policy if exists "Public can view shop settings" on public.shop_settings;
create policy "Public can view shop settings" on public.shop_settings for select to anon, authenticated using (true);
drop policy if exists "Admins manage shop settings" on public.shop_settings;
create policy "Admins manage shop settings" on public.shop_settings for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

-- Customers may submit orders but cannot read or edit any order.
drop policy if exists "Visitors can create orders" on public.orders;
create policy "Visitors can create orders" on public.orders for insert to anon, authenticated with check (true);
drop policy if exists "Admins view orders" on public.orders;
create policy "Admins view orders" on public.orders for select to authenticated using (public.is_store_admin());
drop policy if exists "Admins update orders" on public.orders;
create policy "Admins update orders" on public.orders for update to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

-- Admins can only read their own allow-list row.
drop policy if exists "Admins view own admin record" on public.admin_users;
create policy "Admins view own admin record" on public.admin_users for select to authenticated using (user_id = auth.uid());

insert into public.shop_settings (id) values (1) on conflict (id) do nothing;

insert into public.products (name, description, price, stock, status, image_url)
select v.name, v.description, v.price, v.stock, v.status, v.image_url
from (values
 ('ทาร์ตสตรอว์เบอร์รีครีมวานิลลา','แป้งทาร์ตเนยสดโฮมเมด ไส้คัสตาร์ดวานิลลาแท้ ท็อปด้วยสตรอว์เบอร์รีสดลูกโต',185,12,'ready','assets/tart-strawberry.webp'),
 ('ทาร์ตมิกซ์เบอร์รีโฮมเมด','บลูเบอร์รี ราสป์เบอร์รี และแบล็กเบอร์รีสด บนครีมมาสคาโปเน่',195,10,'ready','assets/tart-mixed-berry.webp'),
 ('ทาร์ตมะม่วงน้ำดอกไม้เสาวรส','มะม่วงน้ำดอกไม้สุกฉ่ำคู่ซอสเสาวรสโฮมเมด หอมสดชื่น',175,8,'ready','assets/tart-mango.webp'),
 ('ทาร์ตองุ่นไซมัสแคท','องุ่นไซมัสแคทไร้เมล็ดกรอบหวาน อบคู่ครีมชีสสูตรพิเศษ',220,20,'preorder','assets/tart-grape.webp'),
 ('ทาร์ตพีชคาราเมลน้ำผึ้ง','ลูกพีชย่างน้ำผึ้งหอมกรุ่นบนอัลมอนด์ครีมและทาร์ตกรอบ',190,20,'preorder','assets/tart-peach.webp')
) as v(name,description,price,stock,status,image_url)
where not exists (select 1 from public.products p where p.name = v.name);

-- After creating your admin in Authentication > Users, replace UUID below and run:
-- insert into public.admin_users (user_id) values ('PASTE-AUTH-USER-UUID-HERE') on conflict do nothing;
