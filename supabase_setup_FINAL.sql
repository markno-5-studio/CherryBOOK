-- ============================================================
-- 小桃記帳　完整建置 SQL（最終版，請只跑這一份就好）
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
--
-- ★ 可重複執行（idempotent）
-- ★ 已修正 v3 的「profiles 權限無限遞迴」嚴重錯誤
--   （改用 is_admin() SECURITY DEFINER 函式判斷管理員，避免遞迴）
-- ★ 本檔包含 v2 + v3 + v4 全部內容，跑這份即可，舊檔不用再跑。
-- ============================================================

-- ───────── 1. 資料表 ─────────
create table if not exists travel_settings (
  id         bigint generated always as identity primary key,
  title      text not null default '新的旅程',
  tag        text default '',
  start_date date,
  end_date   date,
  logo       text,
  owner_id   uuid
);
alter table travel_settings add column if not exists owner_id uuid;

create table if not exists travel_categories (
  id   bigint generated always as identity primary key,
  icon text default '📦',
  name text not null unique,
  sort int default 99
);

create table if not exists travel_expenses (
  id           bigint generated always as identity primary key,
  created_at   timestamptz default now(),
  expense_date date,
  day_theme    text default '',
  item_name    text not null,
  category     text default '購物',
  currency     text default 'TWD',
  amount       numeric,
  amount_twd   numeric,
  is_prepaid   boolean default false,
  is_medical   boolean default false,
  barcode      text default ''
);
alter table travel_expenses
  add column if not exists book_id bigint references travel_settings(id) on delete cascade;

create table if not exists profiles (
  id         uuid primary key,
  username   text not null default '使用者',
  email      text not null default '',
  birthday   date,
  role       text not null default 'user',
  status     text not null default 'active',
  created_at timestamptz default now()
);

create table if not exists user_applications (
  id         bigint generated always as identity primary key,
  username   text not null,
  email      text not null unique,
  birthday   date,
  status     text not null default 'pending',
  created_at timestamptz default now()
);

create table if not exists invite_codes (
  id         bigint generated always as identity primary key,
  code       text not null unique,
  email      text not null,
  is_used    boolean not null default false,
  used_by    uuid,
  created_at timestamptz default now()
);

create table if not exists book_shares (
  id                bigint generated always as identity primary key,
  book_id           bigint not null references travel_settings(id) on delete cascade,
  owner_id          uuid not null,
  shared_with_id    uuid not null,
  shared_with_email text not null default '',
  created_at        timestamptz default now(),
  unique(book_id, shared_with_id)
);

-- ───────── 2. 管理員判斷函式（避免 profiles 權限遞迴）─────────
create or replace function is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;
grant execute on function is_admin() to anon, authenticated;

-- ───────── 3. 開啟 RLS ─────────
alter table travel_settings   enable row level security;
alter table travel_categories enable row level security;
alter table travel_expenses   enable row level security;
alter table profiles          enable row level security;
alter table user_applications enable row level security;
alter table invite_codes      enable row level security;
alter table book_shares       enable row level security;

-- ───────── 4. profiles ─────────
drop policy if exists "profiles select" on profiles;
drop policy if exists "profiles insert" on profiles;
drop policy if exists "profiles update" on profiles;
drop policy if exists "profiles delete" on profiles;
create policy "profiles select" on profiles for select using (auth.uid() = id or is_admin());
create policy "profiles insert" on profiles for insert with check (auth.uid() = id);
create policy "profiles update" on profiles for update using (auth.uid() = id or is_admin());
create policy "profiles delete" on profiles for delete using (is_admin());

-- ───────── 5. user_applications（任何人可送申請；管理員可讀/改）─────────
drop policy if exists "apps public insert" on user_applications;
drop policy if exists "apps admin select" on user_applications;
drop policy if exists "apps admin update" on user_applications;
create policy "apps public insert" on user_applications for insert with check (true);
create policy "apps admin select"  on user_applications for select using (is_admin());
create policy "apps admin update"  on user_applications for update using (is_admin());

-- ───────── 6. invite_codes（任何人可讀以驗證；管理員增刪；認證者可標記已用）─────────
drop policy if exists "codes select"       on invite_codes;
drop policy if exists "codes admin insert" on invite_codes;
drop policy if exists "codes auth update"  on invite_codes;
drop policy if exists "codes admin delete" on invite_codes;
create policy "codes select"       on invite_codes for select using (true);
create policy "codes admin insert" on invite_codes for insert to authenticated with check (is_admin());
create policy "codes auth update"  on invite_codes for update using (is_used = false or is_admin());
create policy "codes admin delete" on invite_codes for delete to authenticated using (is_admin());

-- ───────── 7. travel_settings（本人/被分享者/管理員可讀；本人或管理員可寫）─────────
drop policy if exists "read settings"        on travel_settings;
drop policy if exists "auth insert settings" on travel_settings;
drop policy if exists "auth update settings" on travel_settings;
drop policy if exists "auth delete settings" on travel_settings;
create policy "read settings" on travel_settings for select using (
  owner_id = auth.uid()
  or owner_id is null
  or is_admin()
  or exists (select 1 from book_shares bs where bs.book_id = id and bs.shared_with_id = auth.uid())
);
create policy "auth insert settings" on travel_settings for insert to authenticated
  with check (owner_id = auth.uid());
create policy "auth update settings" on travel_settings for update to authenticated
  using (owner_id = auth.uid() or owner_id is null or is_admin());
create policy "auth delete settings" on travel_settings for delete to authenticated
  using (owner_id = auth.uid() or owner_id is null or is_admin());

-- ───────── 8. travel_expenses（依 book 判斷）─────────
drop policy if exists "read expenses"        on travel_expenses;
drop policy if exists "auth insert expenses" on travel_expenses;
drop policy if exists "auth update expenses" on travel_expenses;
drop policy if exists "auth delete expenses" on travel_expenses;
create policy "read expenses" on travel_expenses for select using (
  exists (
    select 1 from travel_settings ts where ts.id = travel_expenses.book_id
    and (ts.owner_id = auth.uid() or ts.owner_id is null or is_admin()
         or exists (select 1 from book_shares bs where bs.book_id = ts.id and bs.shared_with_id = auth.uid()))
  )
);
create policy "auth insert expenses" on travel_expenses for insert to authenticated with check (
  exists (select 1 from travel_settings ts where ts.id = travel_expenses.book_id
          and (ts.owner_id = auth.uid() or ts.owner_id is null or is_admin()))
);
create policy "auth update expenses" on travel_expenses for update to authenticated using (
  exists (select 1 from travel_settings ts where ts.id = travel_expenses.book_id
          and (ts.owner_id = auth.uid() or ts.owner_id is null or is_admin()))
);
create policy "auth delete expenses" on travel_expenses for delete to authenticated using (
  exists (select 1 from travel_settings ts where ts.id = travel_expenses.book_id
          and (ts.owner_id = auth.uid() or ts.owner_id is null or is_admin()))
);

-- ───────── 9. travel_categories（共用；任何登入者可讀寫）─────────
drop policy if exists "read categories"        on travel_categories;
drop policy if exists "auth insert categories" on travel_categories;
drop policy if exists "auth update categories" on travel_categories;
drop policy if exists "auth delete categories" on travel_categories;
create policy "read categories"        on travel_categories for select using (true);
create policy "auth insert categories" on travel_categories for insert to authenticated with check (true);
create policy "auth update categories" on travel_categories for update to authenticated using (true) with check (true);
create policy "auth delete categories" on travel_categories for delete to authenticated using (true);

-- ───────── 10. book_shares ─────────
drop policy if exists "shares select" on book_shares;
drop policy if exists "shares insert" on book_shares;
drop policy if exists "shares delete" on book_shares;
create policy "shares select" on book_shares for select using (
  owner_id = auth.uid() or shared_with_id = auth.uid() or is_admin()
);
create policy "shares insert" on book_shares for insert to authenticated with check (owner_id = auth.uid());
create policy "shares delete" on book_shares for delete to authenticated using (owner_id = auth.uid() or is_admin());

-- ───────── 11. 用 email 分享帳本（安全函式）─────────
create or replace function share_book(p_book_id bigint, p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid; v_owner uuid;
begin
  select owner_id into v_owner from travel_settings where id = p_book_id;
  if v_owner is distinct from auth.uid() then return 'not_owner'; end if;
  select id into v_uid from profiles where lower(email) = lower(p_email) limit 1;
  if v_uid is null then return 'no_user'; end if;
  if v_uid = auth.uid() then return 'self'; end if;
  insert into book_shares (book_id, owner_id, shared_with_id, shared_with_email)
  values (p_book_id, auth.uid(), v_uid, p_email)
  on conflict (book_id, shared_with_id) do nothing;
  return 'ok';
end;
$$;
grant execute on function share_book(bigint, text) to authenticated;

-- ───────── 12. 即時同步 ─────────
do $$
begin
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'travel_expenses') then
    alter publication supabase_realtime add table travel_expenses;
  end if;
end $$;

-- ───────── 13. 初始分類（僅在空表時塞）─────────
insert into travel_categories (icon, name, sort) values
  ('🍜', '餐飲', 1), ('🚇', '交通', 2), ('🛍️', '購物', 3),
  ('💉', '醫美', 4), ('🏨', '住宿', 5), ('👕', '服飾', 6),
  ('💊', '藥品', 7), ('🍓', '食品零食', 8), ('💍', '飾品配件', 9),
  ('💄', '美妝保養', 10), ('📦', '其他', 99)
on conflict (name) do nothing;

-- ============================================================
-- ★ 管理員設定：登入 markno.5.studio@gmail.com 後，APP 會依
--   程式內 ADMIN_EMAILS 自動把該帳號標記為 admin（status=active）。
-- ★ ⚠ 若想讓「Confirm email 開啟」也能順利註冊，無需特別處理；
--   本系統已改為「先驗證邀請碼才 signUp」，驗證信只會在註冊時寄一次。
-- ============================================================
