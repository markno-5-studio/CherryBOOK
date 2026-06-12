-- ============================================================
-- 管理員「完整刪除使用者」函式（強化版）
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
--
-- ★ 會完整刪除：個人資料、帳本、消費、分享、邀請碼，
--   ★ 連同「申請紀錄(user_applications)」一併刪除
--     → 刪除後同一信箱可以「重新申請邀請碼」
-- ★ 連同 auth.identities / auth.sessions / auth.users 一併刪除
--   → 真正把登入帳號清乾淨（避免外鍵卡住刪不掉）
-- ★ 若刪除過程出錯，會回傳 'error: 原因'，方便前端顯示
-- ============================================================

create or replace function admin_delete_user(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text;
begin
  -- 只有管理員可以呼叫
  if not is_admin() then
    return 'not_admin';
  end if;

  -- 不能刪除自己
  if p_uid = auth.uid() then
    return 'cannot_delete_self';
  end if;

  -- 先取得信箱，等下用來刪除申請紀錄
  select email into v_email from profiles where id = p_uid;
  if v_email is null then
    select email into v_email from auth.users where id = p_uid;
  end if;

  -- 1) 刪除 App 相關資料
  delete from travel_settings  where owner_id = p_uid;
  delete from book_shares      where owner_id = p_uid or shared_with_id = p_uid;
  delete from invite_codes     where used_by = p_uid;
  delete from profiles         where id = p_uid;

  -- 2) 刪除申請紀錄與該信箱的邀請碼（讓同一信箱可重新申請）
  if v_email is not null then
    delete from user_applications where lower(email) = lower(v_email);
    delete from invite_codes      where lower(email) = lower(v_email);
  end if;

  -- 3) 刪除 Auth 登入帳號（先清子表，避免外鍵卡住）
  delete from auth.identities where user_id = p_uid;
  delete from auth.sessions   where user_id = p_uid;
  delete from auth.users      where id = p_uid;

  return 'ok';
exception when others then
  return 'error: ' || SQLERRM;
end;
$$;

grant execute on function admin_delete_user(uuid) to authenticated;
