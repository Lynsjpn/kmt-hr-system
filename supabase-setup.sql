-- ============================================================
-- KMT 人事管理システム — データベース一括セットアップ
--   ・全テーブル作成
--   ・権限レベル（ゲスト／社員／管理者／全体管理）
--   ・RLS（サーバー側の権限チェック）
--   ・許可リストに無いメールの新規登録を拒否するトリガー
-- 何度実行しても安全です（再実行可）。
-- ============================================================

create extension if not exists pgcrypto;

-- 1) テーブル -------------------------------------------------------
create table if not exists public.allowed_users (
  email        text primary key,
  display_name text default '',
  role         text not null default '社員',
  added_at     timestamptz not null default now()
);
alter table public.allowed_users add column if not exists display_name text default '';
alter table public.allowed_users add column if not exists role text not null default '社員';
alter table public.allowed_users drop constraint if exists allowed_users_role_chk;
alter table public.allowed_users add constraint allowed_users_role_chk
  check (role in ('ゲスト','社員','管理者','全体管理'));

create table if not exists public.departments (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  sort_order int default 0
);

create table if not exists public.doc_templates (
  id         text primary key,
  stage      text not null,
  name       text not null,
  tags       text[] not null default '{}',
  note       text default '',
  sort_order int default 0
);

create table if not exists public.employees (
  id                  uuid primary key default gen_random_uuid(),
  emp_no              text default '',
  status              text default '在籍',
  name_kanji          text default '',
  name_kana           text default '',
  name_roma           text default '',
  birth_date          date,
  gender              text default '',
  nationality         text default '',
  is_foreign          boolean default false,
  employment_type     text default '正社員',
  department          text default '',
  position            text default '',
  hire_date           date,
  probation_end       date,
  contract_end        date,
  resign_date         date,
  email               text default '',
  phone               text default '',
  address             text default '',
  emergency_name      text default '',
  emergency_relation  text default '',
  emergency_phone     text default '',
  social_ins          boolean default false,
  emp_ins_no          text default '',
  pension_no          text default '',
  my_number_collected boolean default false,
  zairyu_status       text default '',
  zairyu_card_no      text default '',
  zairyu_expiry       date,
  passport_no         text default '',
  passport_expiry     date,
  toritsugi_expiry    date,
  notes               text default '',
  created_at          timestamptz not null default now()
);

create table if not exists public.employee_docs (
  employee_id uuid not null references public.employees(id) on delete cascade,
  doc_id      text not null,
  status      text default '未依頼',
  date        date,
  note        text default '',
  primary key (employee_id, doc_id)
);

create table if not exists public.evaluations (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid references public.employees(id) on delete cascade,
  period        text default '',
  evaluator     text default '',
  status        text default '目標設定',
  role          text default '紹介営業',
  kpis          jsonb default '[]'::jsonb,
  comps         jsonb default '[]'::jsonb,
  atts          jsonb default '[]'::jsonb,
  sd_reason     text default '',
  mid_review    text default '',
  final_meeting text default '',
  emp_comment   text default '',
  goals         jsonb default '[]'::jsonb,
  self_score    text default '',
  mgr_score     text default '',
  final_grade   text default '',
  comment       text default ''
);

-- 退職者数のように「少ないほど良い」KPIを正しく評価するための区分
-- （達成率を 目標÷実績 で計算する）
create table if not exists public.kpis (
  id          uuid primary key default gen_random_uuid(),
  period      text default '',
  scope       text default '全社',   -- 全社 / 部署 / チーム（国籍別）/ 個人
  employee_id uuid references public.employees(id) on delete set null,
  dept        text default '',
  name        text default '',
  unit        text default '',
  target      text default '',
  records     jsonb default '[]'::jsonb,
  notes       text default ''
);
alter table public.kpis add column if not exists lower_better boolean not null default false;

create table if not exists public.assets (
  id            uuid primary key default gen_random_uuid(),
  asset_no      text default '',
  category      text default 'PC',
  name          text default '',
  serial        text default '',
  purchase_date date,
  price         text default '',
  status        text default '在庫',
  assigned_to   uuid references public.employees(id) on delete set null,
  lend_date     date,
  return_date   date,
  notes         text default ''
);

-- スキル管理（カオナビ型）：スキルマスタ＋社員別レベル
create table if not exists public.skill_defs (
  id          text primary key,
  category    text not null,
  name        text not null,
  description text default '',
  sort_order  int default 0
);
-- 英語併記用（外国籍スタッフ向け。アプリの「スキルマスタ」から編集可）
alter table public.skill_defs add column if not exists name_en        text default '';
alter table public.skill_defs add column if not exists description_en text default '';
alter table public.skill_defs add column if not exists category_en    text default '';
-- スキルごとの具体的タスク [{jp,en},...]。初期データはアプリの
-- 「スキルマスタ > 初期テンプレートに戻す」で投入される（DEFAULT_SKILL_TASKS）
alter table public.skill_defs add column if not exists tasks jsonb not null default '[]'::jsonb;

create table if not exists public.employee_skills (
  employee_id uuid not null references public.employees(id) on delete cascade,
  skill_id    text not null references public.skill_defs(id) on delete cascade,
  level       int not null default 0 check (level between 0 and 5),
  note        text default '',
  updated_at  timestamptz not null default now(),
  primary key (employee_id, skill_id)
);
-- タスクごとの評価 {taskId: 1〜5}。スキル本体の点数はこの平均で決まる
-- （level 列には四捨五入した平均が入る）
alter table public.employee_skills add column if not exists task_levels jsonb not null default '{}'::jsonb;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- 2) 権限判定の関数 -------------------------------------------------
--    security definer にすることで allowed_users のRLSと再帰しない
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role from public.allowed_users
      where lower(email) = lower(auth.jwt() ->> 'email') limit 1),
    'ゲスト');
$$;

create or replace function public.my_rank()
returns int language sql stable security definer set search_path = public as $$
  select case public.my_role()
    when '全体管理' then 3
    when '管理者'   then 2
    when '社員'     then 1
    else 0 end;
$$;

-- 未ログイン(anon)からRPCで呼べないようにし、ログイン済みにだけ許可する
revoke all on function public.my_role() from public, anon;
revoke all on function public.my_rank() from public, anon;
grant execute on function public.my_role() to authenticated;
grant execute on function public.my_rank() to authenticated;

-- 3) 許可リストに無いメールの新規登録を拒否 --------------------------
create or replace function public.enforce_allowed_signup()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.allowed_users where lower(email) = lower(new.email)
  ) then
    raise exception 'signup_not_allowed';
  end if;
  return new;
end $$;

drop trigger if exists enforce_allowed_signup_trg on auth.users;
create trigger enforce_allowed_signup_trg
  before insert on auth.users
  for each row execute function public.enforce_allowed_signup();

-- トリガー専用なのでRPC経由では呼べないようにする（トリガー実行に EXECUTE 権限は不要）
revoke all on function public.enforce_allowed_signup() from public, anon, authenticated;

-- 4) RLS ------------------------------------------------------------
alter table public.allowed_users  enable row level security;
alter table public.departments    enable row level security;
alter table public.doc_templates  enable row level security;
alter table public.employees      enable row level security;
alter table public.employee_docs  enable row level security;
alter table public.evaluations    enable row level security;
alter table public.kpis           enable row level security;
alter table public.assets         enable row level security;

-- allowed_users：閲覧＝自分の行（管理者以上は全員）／変更＝全体管理のみ
drop policy if exists kmt_au_select on public.allowed_users;
drop policy if exists kmt_au_insert on public.allowed_users;
drop policy if exists kmt_au_update on public.allowed_users;
drop policy if exists kmt_au_delete on public.allowed_users;
create policy kmt_au_select on public.allowed_users for select to authenticated
  using (public.my_rank() >= 2 or lower(email) = lower(auth.jwt() ->> 'email'));
create policy kmt_au_insert on public.allowed_users for insert to authenticated
  with check (public.my_rank() >= 3);
create policy kmt_au_update on public.allowed_users for update to authenticated
  using (public.my_rank() >= 3) with check (public.my_rank() >= 3);
create policy kmt_au_delete on public.allowed_users for delete to authenticated
  using (public.my_rank() >= 3);

-- employees：管理者以上は全員／社員は自分の行のみ／ゲストは不可
drop policy if exists kmt_emp_select on public.employees;
drop policy if exists kmt_emp_insert on public.employees;
drop policy if exists kmt_emp_update on public.employees;
drop policy if exists kmt_emp_delete on public.employees;
create policy kmt_emp_select on public.employees for select to authenticated
  using (public.my_rank() >= 2
         or (public.my_rank() = 1 and lower(coalesce(email,'')) = lower(auth.jwt() ->> 'email')));
create policy kmt_emp_insert on public.employees for insert to authenticated
  with check (public.my_rank() >= 2);
create policy kmt_emp_update on public.employees for update to authenticated
  using (public.my_rank() >= 2) with check (public.my_rank() >= 2);
create policy kmt_emp_delete on public.employees for delete to authenticated
  using (public.my_rank() >= 2);

-- employee_docs / evaluations：社員は自分の行のみ閲覧
do $$
declare t text;
begin
  foreach t in array array['employee_docs','evaluations'] loop
    execute format('drop policy if exists kmt_%s_select on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_insert on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_update on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_delete on public.%I', t, t);
    execute format($f$create policy kmt_%s_select on public.%I for select to authenticated
      using (public.my_rank() >= 2
             or (public.my_rank() = 1 and employee_id in (select id from public.employees)))$f$, t, t);
    execute format('create policy kmt_%s_insert on public.%I for insert to authenticated with check (public.my_rank() >= 2)', t, t);
    execute format('create policy kmt_%s_update on public.%I for update to authenticated using (public.my_rank() >= 2) with check (public.my_rank() >= 2)', t, t);
    execute format('create policy kmt_%s_delete on public.%I for delete to authenticated using (public.my_rank() >= 2)', t, t);
  end loop;
end $$;

-- kpis：社員は全社・部署KPI＋自分の個人KPIのみ
drop policy if exists kmt_kpi_select on public.kpis;
drop policy if exists kmt_kpi_insert on public.kpis;
drop policy if exists kmt_kpi_update on public.kpis;
drop policy if exists kmt_kpi_delete on public.kpis;
create policy kmt_kpi_select on public.kpis for select to authenticated
  using (public.my_rank() >= 2
         or (public.my_rank() = 1 and (employee_id is null or employee_id in (select id from public.employees))));
create policy kmt_kpi_insert on public.kpis for insert to authenticated
  with check (public.my_rank() >= 2);
create policy kmt_kpi_update on public.kpis for update to authenticated
  using (public.my_rank() >= 2) with check (public.my_rank() >= 2);
create policy kmt_kpi_delete on public.kpis for delete to authenticated
  using (public.my_rank() >= 2);

-- assets：管理者以上のみ
drop policy if exists kmt_as_select on public.assets;
drop policy if exists kmt_as_insert on public.assets;
drop policy if exists kmt_as_update on public.assets;
drop policy if exists kmt_as_delete on public.assets;
create policy kmt_as_select on public.assets for select to authenticated using (public.my_rank() >= 2);
create policy kmt_as_insert on public.assets for insert to authenticated with check (public.my_rank() >= 2);
create policy kmt_as_update on public.assets for update to authenticated using (public.my_rank() >= 2) with check (public.my_rank() >= 2);
create policy kmt_as_delete on public.assets for delete to authenticated using (public.my_rank() >= 2);

-- departments / doc_templates：閲覧は社員以上／変更は管理者以上
do $$
declare t text;
begin
  foreach t in array array['departments','doc_templates'] loop
    execute format('drop policy if exists kmt_%s_select on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_insert on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_update on public.%I', t, t);
    execute format('drop policy if exists kmt_%s_delete on public.%I', t, t);
    execute format('create policy kmt_%s_select on public.%I for select to authenticated using (public.my_rank() >= 1)', t, t);
    execute format('create policy kmt_%s_insert on public.%I for insert to authenticated with check (public.my_rank() >= 2)', t, t);
    execute format('create policy kmt_%s_update on public.%I for update to authenticated using (public.my_rank() >= 2) with check (public.my_rank() >= 2)', t, t);
    execute format('create policy kmt_%s_delete on public.%I for delete to authenticated using (public.my_rank() >= 2)', t, t);
  end loop;
end $$;

-- skill_defs：閲覧は社員以上／変更は管理者以上
alter table public.skill_defs enable row level security;
drop policy if exists kmt_sd_select on public.skill_defs;
drop policy if exists kmt_sd_insert on public.skill_defs;
drop policy if exists kmt_sd_update on public.skill_defs;
drop policy if exists kmt_sd_delete on public.skill_defs;
create policy kmt_sd_select on public.skill_defs for select to authenticated using (public.my_rank() >= 1);
create policy kmt_sd_insert on public.skill_defs for insert to authenticated with check (public.my_rank() >= 2);
create policy kmt_sd_update on public.skill_defs for update to authenticated using (public.my_rank() >= 2) with check (public.my_rank() >= 2);
create policy kmt_sd_delete on public.skill_defs for delete to authenticated using (public.my_rank() >= 2);

-- employee_skills：社員は自分の行のみ閲覧／変更は管理者以上
alter table public.employee_skills enable row level security;
drop policy if exists kmt_es_select on public.employee_skills;
drop policy if exists kmt_es_insert on public.employee_skills;
drop policy if exists kmt_es_update on public.employee_skills;
drop policy if exists kmt_es_delete on public.employee_skills;
create policy kmt_es_select on public.employee_skills for select to authenticated
  using (public.my_rank() >= 2
         or (public.my_rank() = 1 and employee_id in (select id from public.employees)));
create policy kmt_es_insert on public.employee_skills for insert to authenticated with check (public.my_rank() >= 2);
create policy kmt_es_update on public.employee_skills for update to authenticated using (public.my_rank() >= 2) with check (public.my_rank() >= 2);
create policy kmt_es_delete on public.employee_skills for delete to authenticated using (public.my_rank() >= 2);

-- 4b) スキルの初期テンプレート（空のときだけ投入・再実行安全） --------
insert into public.skill_defs (id, category, category_en, name, name_en, description, description_en, sort_order)
select * from (values
 ('s01','語学・コミュニケーション','Language & Communication','日本語（ビジネス）','Business Japanese','会議・文書・電話応対レベル','Meetings, documents, phone support',1),
 ('s02','語学・コミュニケーション','Language & Communication','英語','English','業務コミュニケーションレベル','Business communication level',2),
 ('s03','語学・コミュニケーション','Language & Communication','多文化コミュニケーション','Cross-cultural Communication','国籍・文化の異なる相手との調整力','Coordinating across nationalities and cultures',3),
 ('s10','紹介営業','Recruitment Sales','新規開拓・アポ獲得','Prospecting & Appointment Setting','','',10),
 ('s11','紹介営業','Recruitment Sales','求人ヒアリング・提案','Job Requirement Analysis & Proposal','','',11),
 ('s12','紹介営業','Recruitment Sales','クロージング・条件交渉','Closing & Terms Negotiation','','',12),
 ('s13','紹介営業','Recruitment Sales','顧客関係維持','Client Relationship Management','既存顧客フォロー・リピート獲得','Follow-up and repeat business',13),
 ('s20','支援業務','Support Services','入管手続き・申請書類','Immigration Procedures & Applications','在留資格の申請・更新・届出','Status applications, renewals, notifications',20),
 ('s21','支援業務','Support Services','生活オリエンテーション','Life Orientation','住居・銀行・行政手続きの案内','Housing, banking, government procedures',21),
 ('s22','支援業務','Support Services','定期面談・相談対応','Regular Interviews & Consultation','','',22),
 ('s23','支援業務','Support Services','行政・関係機関連携','Liaison with Authorities','入管・ハローワーク・支援団体との調整','Immigration Bureau, Hello Work, support organizations',23),
 ('s30','マーケティング','Marketing','SNS運用・発信','Social Media Management','','',30),
 ('s31','マーケティング','Marketing','コンテンツ制作','Content Production','画像・動画・記事の制作','Images, video, articles',31),
 ('s32','マーケティング','Marketing','採用マーケティング','Recruitment Marketing','求職者集客・母集団形成','Candidate attraction and pipeline building',32),
 ('s33','マーケティング','Marketing','データ分析','Data Analysis','数値管理・レポート作成','Metrics management and reporting',33),
 ('s40','バックオフィス','Back Office','労務・勤怠管理','Labor & Attendance Management','','',40),
 ('s41','バックオフィス','Back Office','経理・請求業務','Accounting & Invoicing','','',41),
 ('s42','バックオフィス','Back Office','契約書・文書管理','Contract & Document Management','','',42),
 ('s43','バックオフィス','Back Office','PC・ITツール活用','PC & IT Tools','Excel・クラウドツール等','Excel, cloud tools, etc.',43),
 ('s50','共通・マネジメント','Core & Management','問題解決・改善提案','Problem Solving & Improvement','','',50),
 ('s51','共通・マネジメント','Core & Management','後輩指導・OJT','Mentoring & OJT','','',51),
 ('s52','共通・マネジメント','Core & Management','チームマネジメント','Team Management','','',52),
 ('s53','共通・マネジメント','Core & Management','コンプライアンス理解','Compliance Awareness','個人情報・入管法・労働法の理解','Privacy, immigration law, labor law',53)
) as v(id, category, category_en, name, name_en, description, description_en, sort_order)
where not exists (select 1 from public.skill_defs);

-- 5) 最初の全体管理者 -----------------------------------------------
--    ここで登録するのはメールアドレスと権限だけです。
--    パスワードは本人がログイン画面の「新規登録（初回のみ）」で設定します。
do $$
begin
  if exists (select 1 from public.allowed_users where lower(email) = 'nisa@k-m-t.jp') then
    update public.allowed_users
       set role = '全体管理', display_name = coalesce(nullif(display_name,''), 'Nisa')
     where lower(email) = 'nisa@k-m-t.jp';
  else
    insert into public.allowed_users (email, display_name, role)
    values ('nisa@k-m-t.jp', 'Nisa', '全体管理');
  end if;
end $$;

select email, display_name, role from public.allowed_users order by role, email;
