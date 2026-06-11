-- ============================================================
-- 旅遊記帳系統 v2（Supabase Auth 版）建表 SQL
-- 使用方式：Supabase 後台 → SQL Editor → 貼上 → Run
--
-- ★ 與 v1 的差異：
--   1. 改用 Supabase Auth：密碼不再存資料表，寫入權限只開放給「已登入」使用者
--   2. 多幣別：每筆消費記「原幣金額 + 幣別 + 台幣金額」
--   3. 新增 travel_categories 分類表（Emoji 圖示可編輯）
--   4. travel_settings 新增 logo 欄位（存 base64 圖片）
-- ============================================================

-- 若你已執行過 v1，先清掉舊表（沒有資料要保留的話）：
-- drop table if exists travel_expenses; drop table if exists travel_settings;

-- 1. 帳本設定
create table if not exists travel_settings (
  id         bigint generated always as identity primary key,
  title      text not null default '首爾之旅',
  tag        text default '2026 春 🌸',
  start_date date,
  end_date   date,
  logo       text          -- 首頁 Logo（base64 data URL，null 則用預設 icons/logo.png）
);

-- 2. 消費分類（Emoji + 名稱皆可在後台編輯）
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
  expense_date date,                      -- 消費日期（依此分組）
  day_theme    text default '',           -- 當日主題（支援 Emoji）
  item_name    text not null,             -- 項目名稱（支援 Emoji，可隨時改）
  category     text default '購物',
  currency     text default 'TWD',        -- 原幣別：TWD / KRW / JPY / USD…
  amount       numeric,                   -- 原幣金額
  amount_twd   numeric,                   -- 台幣金額（自動換算或手動輸入）
  is_prepaid   boolean default false,
  is_medical   boolean default false,
  barcode      text default ''
);

-- 4. Row Level Security：任何人可「讀」，只有登入者可「寫」
alter table travel_settings   enable row level security;
alter table travel_categories enable row level security;
alter table travel_expenses   enable row level security;

create policy "read settings"   on travel_settings   for select using (true);
create policy "read categories" on travel_categories for select using (true);
create policy "read expenses"   on travel_expenses   for select using (true);

create policy "auth write settings"   on travel_settings   for update to authenticated using (true) with check (true);
create policy "auth insert categories" on travel_categories for insert to authenticated with check (true);
create policy "auth update categories" on travel_categories for update to authenticated using (true) with check (true);
create policy "auth delete categories" on travel_categories for delete to authenticated using (true);
create policy "auth insert expenses" on travel_expenses for insert to authenticated with check (true);
create policy "auth update expenses" on travel_expenses for update to authenticated using (true) with check (true);
create policy "auth delete expenses" on travel_expenses for delete to authenticated using (true);

-- 5. 即時同步
alter publication supabase_realtime add table travel_expenses;

-- 6. 初始資料
insert into travel_settings (title, tag, start_date, end_date)
values ('首爾醫美購物之旅', '2026 春 🌸', '2026-03-28', '2026-04-03');

insert into travel_categories (icon, name, sort) values
  ('🍜', '餐飲', 1), ('🚇', '交通', 2), ('🛍️', '購物', 3),
  ('💉', '醫美', 4), ('🏨', '住宿', 5), ('👕', '服飾', 6),
  ('💊', '藥品', 7), ('🍓', '食品零食', 8), ('💍', '飾品配件', 9),
  ('💄', '美妝保養', 10), ('📦', '其他', 99);

-- ============================================================
-- ★ 建立管理員帳號（必做，不在 SQL 裡）：
--   Supabase 後台 → Authentication → Users → Add user →
--   「Create new user」輸入 Email + 密碼，勾選 Auto Confirm User。
--   之後就用這組 Email / 密碼在網頁上登入。
--
-- ★ 建議順手關閉公開註冊，避免陌生人自行開帳號取得寫入權：
--   Authentication → Sign In / Up → 關閉「Allow new users to sign up」
-- ============================================================
