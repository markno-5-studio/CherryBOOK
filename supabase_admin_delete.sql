-- ============================================================
-- 管理員刪除使用者函式（包含 Auth 帳號）
-- 使用方式：Supabase SQL Editor → 貼上 → Run
-- ============================================================

create or replace function admin_delete_user(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- 只有管理員可以呼叫
  if not is_admin() then
    return 'not_admin';
  end if;

  -- 不能刪除自己
  if p_uid = auth.uid() then
    return 'cannot_delete_self';
  end if;

  -- 刪除所有相關資料（帳本 cascade 會一併刪消費）
  delete from travel_settings  where owner_id = p_uid;
  delete from book_shares      where owner_id = p_uid or shared_with_id = p_uid;
  delete from invite_codes     where used_by = p_uid;
  delete from profiles         where id = p_uid;

  -- 刪除 Auth 登入帳號
  delete from auth.users where id = p_uid;

  return 'ok';
end;
$$;

grant execute on function admin_delete_user(uuid) to authenticated;
