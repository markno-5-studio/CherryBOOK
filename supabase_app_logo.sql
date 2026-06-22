-- ============================================================
-- 小桃記帳 × CherryBOOK：全站設定表 app_settings
-- 使用方式：Supabase → 選到 CherryBOOK 專案 → SQL Editor → 貼上 → Run
--
-- ★ 可重複執行
-- ★ 存放：全站 Logo、主題顏色、EmailJS 設定（管理員可在後台改）
--   只有一列（id=1）。任何人可讀，只有管理員可改。
-- ============================================================

create table if not exists app_settings (
  id   int primary key default 1,
  logo text,
  constraint app_settings_singleton check (id = 1)
);

-- 新增欄位（已存在則略過）
alter table app_settings add column if not exists theme_color     text;   -- 主題色（#hex）
alter table app_settings add column if not exists emailjs_service text;   -- EmailJS Service ID
alter table app_settings add column if not exists emailjs_template text;  -- EmailJS Template ID
alter table app_settings add column if not exists emailjs_public  text;   -- EmailJS Public Key
alter table app_settings add column if not exists notify_email    text;   -- 申請通知信箱
alter table app_settings add column if not exists admin_emails    text;   -- 管理員 Email 清單（逗號分隔）

-- 確保有預設那一列
insert into app_settings (id) values (1) on conflict (id) do nothing;

alter table app_settings enable row level security;

drop policy if exists "app_settings read"  on app_settings;
drop policy if exists "app_settings write" on app_settings;
create policy "app_settings read"  on app_settings for select using (true);
create policy "app_settings write" on app_settings for update to authenticated using (is_admin()) with check (is_admin());

notify pgrst, 'reload schema';
