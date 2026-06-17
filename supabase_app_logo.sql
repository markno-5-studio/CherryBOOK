-- ============================================================
-- 小桃記帳 × CherryBOOK：全站 Logo 設定表
-- 使用方式：Supabase → 選到 CherryBOOK 專案 → SQL Editor → 貼上 → Run
--
-- ★ 可重複執行
-- ★ 用途：登入頁與全站預設 Logo，管理員可在「管理後台」隨時更換。
--   只有一列（id=1）。任何人可讀，只有管理員可改。
-- ============================================================

create table if not exists app_settings (
  id   int primary key default 1,
  logo text,
  constraint app_settings_singleton check (id = 1)
);

-- 確保有預設那一列
insert into app_settings (id) values (1) on conflict (id) do nothing;

alter table app_settings enable row level security;

drop policy if exists "app_settings read"  on app_settings;
drop policy if exists "app_settings write" on app_settings;
create policy "app_settings read"  on app_settings for select using (true);
create policy "app_settings write" on app_settings for update to authenticated using (is_admin()) with check (is_admin());

notify pgrst, 'reload schema';
