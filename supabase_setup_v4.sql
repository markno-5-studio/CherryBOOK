-- ============================================================
-- 小桃記帳 v4 補強 SQL（請先跑過 v3，再跑這份）
-- 使用方式：Supabase 後台 → SQL Editor → 貼上整份 → Run
--
-- ★ 本腳本可重複執行（idempotent）
-- ★ v4 新增 / 修正：
--   1. 管理員可「刪除」使用者 profile（v3 只有 select/insert/update）
--   2. 管理員可刪除 / 修改「任何人」的帳本與消費（後台清資料用）
--   3. share_book() 安全函式：用 email 把帳本分享給別人
--      （一般使用者看不到別人的 profile，所以必須用 SECURITY DEFINER 函式查 id）
--   4. ⚠ 重要：請到 Authentication → Providers → Email
--      關閉「Confirm email」，否則使用者註冊後要收信才能登入。
-- ============================================================

-- 1. 管理員可刪除使用者 profile
drop policy if exists "profiles delete" on profiles;
create policy "profiles delete" on profiles for delete using (
  exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
);

-- 2. 帳本：擁有者或「管理員」可修改 / 刪除
drop policy if exists "auth update settings" on travel_settings;
drop policy if exists "auth delete settings" on travel_settings;
create policy "auth update settings" on travel_settings for update to authenticated using (
  owner_id = auth.uid()
  or owner_id is null
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
);
create policy "auth delete settings" on travel_settings for delete to authenticated using (
  owner_id = auth.uid()
  or owner_id is null
  or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
);

-- 2b. 消費：擁有者（透過 book）或管理員可刪 / 改
drop policy if exists "auth update expenses" on travel_expenses;
drop policy if exists "auth delete expenses" on travel_expenses;
create policy "auth update expenses" on travel_expenses for update to authenticated using (
  exists (
    select 1 from travel_settings ts where ts.id = travel_expenses.book_id
    and (ts.owner_id = auth.uid() or ts.owner_id is null
         or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin'))
  )
);
create policy "auth delete expenses" on travel_expenses for delete to authenticated using (
  exists (
    select 1 from travel_settings ts where ts.id = travel_expenses.book_id
    and (ts.owner_id = auth.uid() or ts.owner_id is null
         or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin'))
  )
);

-- 3. 用 email 分享帳本（一般使用者無法直接查別人 id，所以用安全函式）
create or replace function share_book(p_book_id bigint, p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid;
  v_owner uuid;
begin
  select owner_id into v_owner from travel_settings where id = p_book_id;
  if v_owner is distinct from auth.uid() then
    return 'not_owner';
  end if;

  select id into v_uid from profiles where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    return 'no_user';
  end if;
  if v_uid = auth.uid() then
    return 'self';
  end if;

  insert into book_shares (book_id, owner_id, shared_with_id, shared_with_email)
  values (p_book_id, auth.uid(), v_uid, p_email)
  on conflict (book_id, shared_with_id) do nothing;

  return 'ok';
end;
$$;

grant execute on function share_book(bigint, text) to authenticated;
