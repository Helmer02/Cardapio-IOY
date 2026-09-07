-- Plataforma Fast Burg: contas empresariais, licenças e gestão global.
-- Execute após 20260907_create_restaurant_system.sql.

create table if not exists public.restaurant_companies (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  trade_name text,
  document_number text,
  billing_email text,
  billing_phone text,
  status text not null default 'active' check (status in ('trial', 'active', 'suspended', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.restaurant_restaurants
  add column if not exists company_id uuid references public.restaurant_companies(id) on delete restrict;

create index if not exists restaurant_restaurants_company_idx on public.restaurant_restaurants(company_id);

create table if not exists public.restaurant_company_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.restaurant_companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'owner' check (role in ('owner', 'manager', 'billing')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, user_id)
);

create table if not exists public.restaurant_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  monthly_price numeric(12,2) not null check (monthly_price >= 0),
  max_restaurants integer not null default 1 check (max_restaurants > 0),
  max_users integer not null default 3 check (max_users > 0),
  features jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_licenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.restaurant_companies(id) on delete restrict,
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete restrict,
  plan_id uuid not null references public.restaurant_plans(id) on delete restrict,
  status text not null default 'trial' check (status in ('trial', 'active', 'suspended', 'cancelled')),
  monthly_price numeric(12,2) not null check (monthly_price >= 0),
  starts_at timestamptz not null default now(),
  trial_ends_at timestamptz,
  renews_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurant_id)
);

create table if not exists public.restaurant_billing_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.restaurant_companies(id) on delete restrict,
  license_id uuid references public.restaurant_licenses(id) on delete set null,
  reference_month date not null,
  amount numeric(12,2) not null check (amount >= 0),
  due_date date,
  paid_at timestamptz,
  status text not null default 'open' check (status in ('draft', 'open', 'paid', 'overdue', 'void')),
  external_reference text,
  created_at timestamptz not null default now(),
  unique (company_id, license_id, reference_month)
);

create table if not exists public.restaurant_platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now()
);

create index if not exists restaurant_licenses_company_status_idx on public.restaurant_licenses(company_id, status);
create index if not exists restaurant_invoices_company_status_idx on public.restaurant_billing_invoices(company_id, status, due_date);

create or replace function public.restaurant_platform_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.restaurant_platform_admins where user_id = auth.uid());
$$;

create or replace function public.restaurant_is_company_member(target_company uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.restaurant_company_members where company_id=target_company and user_id=auth.uid() and is_active);
$$;

grant execute on function public.restaurant_platform_is_admin() to authenticated;
grant execute on function public.restaurant_is_company_member(uuid) to authenticated;

create or replace function public.restaurant_create_account(
  p_company_name text,
  p_restaurant_slug text,
  p_document_number text default null,
  p_billing_phone text default null,
  p_plan_code text default 'starter',
  p_restaurant_name text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_company public.restaurant_companies;
  v_restaurant public.restaurant_restaurants;
  v_plan public.restaurant_plans;
  v_display_name text;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if coalesce(trim(p_company_name),'')='' then raise exception 'Nome da empresa obrigatório'; end if;
  if p_restaurant_slug !~ '^[a-z0-9-]+$' then raise exception 'Slug inválido'; end if;
  select * into v_plan from public.restaurant_plans where code=p_plan_code and is_active;
  if not found then raise exception 'Plano indisponível'; end if;
  if exists(select 1 from public.restaurant_restaurants where slug=p_restaurant_slug) then raise exception 'Este endereço já está em uso'; end if;

  v_display_name := coalesce(auth.jwt()->'user_metadata'->>'full_name', split_part(coalesce(auth.jwt()->>'email','Gestor'), '@', 1));
  insert into public.restaurant_companies (legal_name, trade_name, document_number, billing_email, billing_phone, status)
  values (trim(p_company_name), trim(p_company_name), nullif(trim(p_document_number),''), auth.jwt()->>'email', nullif(trim(p_billing_phone),''), 'trial') returning * into v_company;
  insert into public.restaurant_company_members (company_id, user_id, display_name, role)
  values (v_company.id, auth.uid(), v_display_name, 'owner');
  insert into public.restaurant_restaurants (company_id, name, slug, phone)
  values (v_company.id, coalesce(nullif(trim(p_restaurant_name), ''), trim(p_company_name)), p_restaurant_slug, nullif(trim(p_billing_phone),'')) returning * into v_restaurant;
  insert into public.restaurant_staff (restaurant_id, user_id, display_name, role)
  values (v_restaurant.id, auth.uid(), v_display_name, 'owner');
  insert into public.restaurant_licenses (company_id, restaurant_id, plan_id, status, monthly_price, trial_ends_at)
  values (v_company.id, v_restaurant.id, v_plan.id, 'trial', v_plan.monthly_price, now() + interval '14 days');
  return jsonb_build_object('company_id',v_company.id,'restaurant_id',v_restaurant.id,'slug',v_restaurant.slug,'plan',v_plan.name);
end;
$$;

grant execute on function public.restaurant_create_account(text, text, text, text, text, text) to authenticated;

alter table public.restaurant_companies enable row level security;
alter table public.restaurant_company_members enable row level security;
alter table public.restaurant_plans enable row level security;
alter table public.restaurant_licenses enable row level security;
alter table public.restaurant_billing_invoices enable row level security;
alter table public.restaurant_platform_admins enable row level security;

-- Permite executar novamente esta migração após uma interrupção no SQL Editor.
drop policy if exists "platform plans public" on public.restaurant_plans;
drop policy if exists "company members view company" on public.restaurant_companies;
drop policy if exists "company members manage company" on public.restaurant_companies;
drop policy if exists "company members list" on public.restaurant_company_members;
drop policy if exists "company licenses view" on public.restaurant_licenses;
drop policy if exists "company invoices view" on public.restaurant_billing_invoices;
drop policy if exists "platform admins read companies" on public.restaurant_companies;
drop policy if exists "platform admins read restaurants" on public.restaurant_restaurants;
drop policy if exists "platform admins manage licenses" on public.restaurant_licenses;
drop policy if exists "platform admins manage invoices" on public.restaurant_billing_invoices;
drop policy if exists "platform admins read membership" on public.restaurant_company_members;
drop policy if exists "platform admins read admin list" on public.restaurant_platform_admins;

create policy "platform plans public" on public.restaurant_plans for select to anon, authenticated using (is_active);
create policy "company members view company" on public.restaurant_companies for select to authenticated using (public.restaurant_is_company_member(id) or public.restaurant_platform_is_admin());
create policy "company members manage company" on public.restaurant_companies for update to authenticated using (public.restaurant_is_company_member(id) or public.restaurant_platform_is_admin()) with check (public.restaurant_is_company_member(id) or public.restaurant_platform_is_admin());
create policy "company members list" on public.restaurant_company_members for select to authenticated using (public.restaurant_is_company_member(company_id) or public.restaurant_platform_is_admin());
create policy "company licenses view" on public.restaurant_licenses for select to authenticated using (public.restaurant_is_company_member(company_id) or public.restaurant_platform_is_admin());
create policy "company invoices view" on public.restaurant_billing_invoices for select to authenticated using (public.restaurant_is_company_member(company_id) or public.restaurant_platform_is_admin());
create policy "platform admins read companies" on public.restaurant_companies for select to authenticated using (public.restaurant_platform_is_admin());
create policy "platform admins read restaurants" on public.restaurant_restaurants for select to authenticated using (public.restaurant_platform_is_admin());
create policy "platform admins manage licenses" on public.restaurant_licenses for all to authenticated using (public.restaurant_platform_is_admin()) with check (public.restaurant_platform_is_admin());
create policy "platform admins manage invoices" on public.restaurant_billing_invoices for all to authenticated using (public.restaurant_platform_is_admin()) with check (public.restaurant_platform_is_admin());
create policy "platform admins read membership" on public.restaurant_company_members for select to authenticated using (public.restaurant_platform_is_admin());
create policy "platform admins read admin list" on public.restaurant_platform_admins for select to authenticated using (public.restaurant_platform_is_admin());

drop trigger if exists restaurant_companies_updated_at on public.restaurant_companies;
create trigger restaurant_companies_updated_at before update on public.restaurant_companies for each row execute function public.restaurant_set_updated_at();
drop trigger if exists restaurant_licenses_updated_at on public.restaurant_licenses;
create trigger restaurant_licenses_updated_at before update on public.restaurant_licenses for each row execute function public.restaurant_set_updated_at();

-- Planos iniciais da plataforma.
insert into public.restaurant_plans (code, name, monthly_price, max_restaurants, max_users, features) values
  ('starter', 'Starter', 99.90, 1, 3, '{"delivery":true,"whatsapp":true,"printing":true}'::jsonb),
  ('pro', 'Pro', 199.90, 3, 10, '{"delivery":true,"whatsapp":true,"printing":true,"analytics":true}'::jsonb),
  ('enterprise', 'Enterprise', 499.90, 20, 50, '{"delivery":true,"whatsapp":true,"printing":true,"analytics":true,"multi_store":true}'::jsonb)
on conflict (code) do update set name=excluded.name, monthly_price=excluded.monthly_price, max_restaurants=excluded.max_restaurants, max_users=excluded.max_users, features=excluded.features, is_active=true;
