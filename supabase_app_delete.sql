-- ============================================================
-- 小桃記帳　補充 SQL：管理員「刪除帳號申請」安全函式
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
--
-- ⚠⚠ 一定要跑在「App 實際連線的專案」上！⚠⚠
--    打開 Supabase 後，左上角專案要選到 App index.html 裡
--    SUPABASE_URL 對應的那個專案（ipvyroculwdsemxwxlna），
--    不要跑在別的專案（例如另一個叫 CherryBOOK 的專案）。
--
-- ★ 可重複執行（idempotent）
-- ★ 用途：後台「帳號申請」清單的刪除鈕。
--   刪除申請紀錄 + 該信箱未使用的邀請碼 → 對方可重新申請、拿新碼。
-- ★ 用 SECURITY DEFINER 函式（與 admin_delete_user 同做法），
--   不受 RLS 影響，且會明確回傳 ok / not_admin / error。
-- ============================================================

create or replace function admin_delete_application(p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 只有管理員可呼叫
  if not is_admin() then
    return 'not_admin';
  end if;

  -- 刪除該信箱「未使用」的邀請碼，讓舊碼失效
  delete from invite_codes where lower(email) = lower(p_email) and is_used = false;

  -- 刪除申請紀錄 → 同一信箱即可重新「申請使用」
  delete from user_applications where lower(email) = lower(p_email);

  return 'ok';
exception when others then
  return 'error: ' || SQLERRM;
end;
$$;

grant execute on function admin_delete_application(text) to authenticated;

-- （保險）也補上 RLS 刪除權限，讓直接 delete 也能用
drop policy if exists "apps admin delete" on user_applications;
create policy "apps admin delete" on user_applications for delete using (is_admin());

drop policy if exists "codes admin delete" on invite_codes;
create policy "codes admin delete" on invite_codes for delete to authenticated using (is_admin());

-- 重整 PostgREST schema 快取（讓新函式立即可呼叫）
notify pgrst, 'reload schema';
