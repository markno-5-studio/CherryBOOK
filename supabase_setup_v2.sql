-- ============================================================
-- 旅遊記帳系統 v3（多帳本 / 專案版）建表 SQL
-- 使用方式：Supabase 後台 → SQL Editor → 貼上「整份內容」→ Run
--
-- ★ 本腳本可重複執行（idempotent）：
--   - 權限規則(policy)會先刪再建，不會再出現「already exists」
--   - 初始資料只在資料表為空時才塞入，不會重複
--
-- ★ v3 新增：多帳本 / 多專案
--   - travel_settings 每一列 = 一本帳本（例：首爾購物之旅、日本購物之旅、日常生活）
--   - travel_expenses 新增 book_id，標記這筆消費屬於哪一本帳本
-- ============================================================

-- 1. 帳本設定（每一列 = 一個專案）
create table if not exists travel_settings (
  id         bigint generated always as identity primary key,
  title      text not null default '新的旅程',
  tag        text default '',
  start_date date,
  end_date   date,
  logo       text          -- 首頁 Logo（base64 data URL，null 則用預設 icons/logo.png）
);

-- 2. 消費分類（所有帳本共用；Emoji + 名稱皆可在後台編輯）
create table if not exists travel_categories (
  id   bigint generated always as identity primary key,
  icon text default '📦',
  name text not null unique,
  sort int default 99
);

-- 3. 消費明細（多幣別）
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

-- 3b. 多帳本：消費歸屬於哪一本帳本（刪帳本時，底下消費一併刪除）
alter table travel_expenses
  add column if not exists book_id bigint references travel_settings(id) on delete cascade;

-- 4. Row Level Security：任何人可「讀」，只有登入者可「寫」
alter table travel_settings   enable row level security;
alter table travel_categories enable row level security;
alter table travel_expenses   enable row level security;

-- 讀取（公開）
drop policy if exists "read settings"   on travel_settings;
drop policy if exists "read categories" on travel_categories;
drop policy if exists "read expenses"   on travel_expenses;
create policy "read settings"   on travel_settings   for select using (true);
create policy "read categories" on travel_categories for select using (true);
create policy "read expenses"   on travel_expenses   for select using (true);

-- 帳本：登入者可新增 / 修改 / 刪除（多帳本需要 insert 與 delete）
drop policy if exists "auth insert settings" on travel_settings;
drop policy if exists "auth update settings" on travel_settings;
drop policy if exists "auth delete settings" on travel_settings;
create policy "auth insert settings" on travel_settings for insert to authenticated with check (true);
create policy "auth update settings" on travel_settings for update to authenticated using (true) with check (true);
create policy "auth delete settings" on travel_settings for delete to authenticated using (true);

-- 分類：登入者可增刪改
drop policy if exists "auth insert categories" on travel_categories;
drop policy if exists "auth update categories" on travel_categories;
drop policy if exists "auth delete categories" on travel_categories;
create policy "auth insert categories" on travel_categories for insert to authenticated with check (true);
create policy "auth update categories" on travel_categories for update to authenticated using (true) with check (true);
create policy "auth delete categories" on travel_categories for delete to authenticated using (true);

-- 消費：登入者可增刪改
drop policy if exists "auth insert expenses" on travel_expenses;
drop policy if exists "auth update expenses" on travel_expenses;
drop policy if exists "auth delete expenses" on travel_expenses;
create policy "auth insert expenses" on travel_expenses for insert to authenticated with check (true);
create policy "auth update expenses" on travel_expenses for update to authenticated using (true) with check (true);
create policy "auth delete expenses" on travel_expenses for delete to authenticated using (true);

-- 5. 即時同步（已加過就略過，不報錯）
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'travel_expenses'
  ) then
    alter publication supabase_realtime add table travel_expenses;
  end if;
end $$;

-- 6. 初始資料（只在資料表為空時才塞，避免重複）
insert into travel_settings (title, tag, start_date, end_date)
select '首爾醫美購物之旅', '2026 春 🌸', '2026-03-28', '2026-04-03'
where not exists (select 1 from travel_settings);

insert into travel_categories (icon, name, sort) values
  ('🍜', '餐飲', 1), ('🚇', '交通', 2), ('🛍️', '購物', 3),
  ('💉', '醫美', 4), ('🏨', '住宿', 5), ('👕', '服飾', 6),
  ('💊', '藥品', 7), ('🍓', '食品零食', 8), ('💍', '飾品配件', 9),
  ('💄', '美妝保養', 10), ('📦', '其他', 99)
on conflict (name) do nothing;

-- ============================================================
-- ★ 管理員帳號（你已建立 markno.5.studio@gmail.com，無需重做）
-- ★ 建議關閉公開註冊：Authentication → Sign In / Up → 關閉「Allow new users to sign up」
-- ============================================================
