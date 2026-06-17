-- ============================================================
-- 小桃記帳　補充 SQL：讓管理員可「刪除帳號申請紀錄」
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
--
-- ★ 可重複執行（idempotent）
-- ★ 用途：後台「帳號申請」清單的刪除鈕需要此權限。
--   刪除申請紀錄後，同一信箱即可「重新申請使用」。
--   （前端會一併刪除核發給該信箱、尚未使用的邀請碼）
-- ============================================================

-- 管理員可刪除 user_applications
drop policy if exists "apps admin delete" on user_applications;
create policy "apps admin delete" on user_applications for delete using (is_admin());

-- invite_codes 的管理員刪除權限（supabase_setup_FINAL.sql 已建立；此處保險再建一次）
drop policy if exists "codes admin delete" on invite_codes;
create policy "codes admin delete" on invite_codes for delete to authenticated using (is_admin());

-- 重整 PostgREST schema 快取
notify pgrst, 'reload schema';
