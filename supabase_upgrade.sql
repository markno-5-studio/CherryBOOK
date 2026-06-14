-- ============================================================
-- 小桃記帳　升級 SQL（日常生活模式 + 預算）
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
-- ★ 可重複執行（idempotent）
-- ============================================================

-- 1) 帳本新增「日常生活模式」與「總預算」欄位
alter table travel_settings add column if not exists is_daily boolean default false;
alter table travel_settings add column if not exists budget   numeric;

-- 2) 新增「日常生活」消費分類（任何國家都能用的日常記帳）
insert into travel_categories (icon, name, sort) values
  ('🏠', '日常生活', 12)
on conflict (name) do nothing;

-- 3) 重整 PostgREST schema 快取（沒這行有時新欄位讀不到，會出現
--    "Could not find the 'is_daily' column ... in the schema cache"）
notify pgrst, 'reload schema';
