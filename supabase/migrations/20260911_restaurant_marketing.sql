-- Cupons, fidelidade por pedidos entregues e campanhas manuais de WhatsApp.
create table if not exists public.restaurant_coupons (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id),
  code text not null check (code ~ '^[A-Z0-9_-]{3,40}$'),
  kind text not null check (kind in ('fixed','percent')),
  amount numeric(12,2) not null check (amount > 0),
  minimum_total numeric(12,2) not null default 0 check (minimum_total >= 0),
  expires_at timestamptz,
  usage_limit integer check (usage_limit > 0),
  used_count integer not null default 0 check (used_count >= 0),
  active boolean not null default true,
  customer_phone text,
  created_at timestamptz not null default now(),
  unique(restaurant_id,code),
  check (kind <> 'percent' or amount <= 100)
);
create table if not exists public.restaurant_loyalty_settings (
  restaurant_id uuid primary key references public.restaurant_restaurants(id),
  enabled boolean not null default false,
  target_orders integer not null default 10 check (target_orders between 2 and 100),
  reward_amount numeric(12,2) not null default 10 check (reward_amount > 0)
);
create table if not exists public.restaurant_marketing_customers (
  restaurant_id uuid not null references public.restaurant_restaurants(id),
  phone text not null check (phone ~ '^55[0-9]{10,11}$'),
  name text not null default '',
  opted_in boolean not null default false,
  consent_at timestamptz,
  stamps integer not null default 0 check (stamps >= 0),
  delivered_orders integer not null default 0,
  last_order_at timestamptz,
  primary key(restaurant_id,phone)
);
create table if not exists public.restaurant_loyalty_events (
  order_id uuid primary key references public.restaurant_orders(id),
  restaurant_id uuid not null references public.restaurant_restaurants(id),
  phone text not null,
  reward_coupon_id uuid references public.restaurant_coupons(id),
  created_at timestamptz not null default now()
);
create table if not exists public.restaurant_campaigns (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id),
  name text not null check (length(trim(name)) between 1 and 100),
  message text not null check (length(trim(message)) between 1 and 2000),
  audience text not null default 'all' check (audience in ('all','inactive','loyal')),
  created_at timestamptz not null default now()
);
create table if not exists public.restaurant_campaign_opens (
  campaign_id uuid not null references public.restaurant_campaigns(id),
  restaurant_id uuid not null references public.restaurant_restaurants(id),
  phone text not null,
  opened_at timestamptz not null default now(),
  primary key(campaign_id,phone)
);
alter table public.restaurant_orders add column if not exists coupon_id uuid references public.restaurant_coupons(id);
alter table public.restaurant_orders add column if not exists marketing_opt_in boolean not null default false;

alter table public.restaurant_coupons enable row level security;
alter table public.restaurant_loyalty_settings enable row level security;
alter table public.restaurant_marketing_customers enable row level security;
alter table public.restaurant_loyalty_events enable row level security;
alter table public.restaurant_campaigns enable row level security;
alter table public.restaurant_campaign_opens enable row level security;
create policy "marketing coupons read" on public.restaurant_coupons for select to authenticated using(public.restaurant_is_staff(restaurant_id));
create policy "marketing coupons create" on public.restaurant_coupons for insert to authenticated with check(public.restaurant_is_staff(restaurant_id) and used_count = 0 and customer_phone is null);
create policy "marketing coupons toggle" on public.restaurant_coupons for update to authenticated using(public.restaurant_is_staff(restaurant_id)) with check(public.restaurant_is_staff(restaurant_id));
create policy "marketing settings" on public.restaurant_loyalty_settings for all to authenticated using(public.restaurant_is_staff(restaurant_id)) with check(public.restaurant_is_staff(restaurant_id));
create policy "marketing customers read" on public.restaurant_marketing_customers for select to authenticated using(public.restaurant_is_staff(restaurant_id));
create policy "marketing customers optout" on public.restaurant_marketing_customers for update to authenticated using(public.restaurant_is_staff(restaurant_id)) with check(public.restaurant_is_staff(restaurant_id) and not opted_in);
create policy "marketing events read" on public.restaurant_loyalty_events for select to authenticated using(public.restaurant_is_staff(restaurant_id));
create policy "marketing campaigns read" on public.restaurant_campaigns for select to authenticated using(public.restaurant_is_staff(restaurant_id));
create policy "marketing campaigns create" on public.restaurant_campaigns for insert to authenticated with check(public.restaurant_is_staff(restaurant_id));
create policy "marketing opens read" on public.restaurant_campaign_opens for select to authenticated using(public.restaurant_is_staff(restaurant_id));
-- O cliente não pode alterar contadores ou cadastrar consentimento pelo REST.
revoke all on public.restaurant_coupons, public.restaurant_loyalty_settings, public.restaurant_marketing_customers,
  public.restaurant_loyalty_events, public.restaurant_campaigns, public.restaurant_campaign_opens from anon, authenticated;
grant select, insert on public.restaurant_coupons to authenticated;
grant update(active) on public.restaurant_coupons to authenticated;
grant select, insert, update on public.restaurant_loyalty_settings to authenticated;
grant select on public.restaurant_marketing_customers, public.restaurant_loyalty_events, public.restaurant_campaign_opens to authenticated;
grant select, insert on public.restaurant_campaigns to authenticated;
grant update(opted_in) on public.restaurant_marketing_customers to authenticated;

create or replace function public.restaurant_normalize_phone(p_phone text)
returns text language sql immutable set search_path = public as $$
  select case when length(digits) in (10,11) then '55'||digits
    when digits ~ '^55[0-9]{10,11}$' then digits else null end
  from (select regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') as digits) p;
$$;

create or replace function public.restaurant_marketing_submit_order(
  p_restaurant_slug text, p_channel text, p_items jsonb,
  p_table_code text default null, p_customer_name text default null,
  p_customer_phone text default null, p_delivery_address jsonb default '{}'::jsonb,
  p_coupon_code text default null, p_marketing_opt_in boolean default false
)
returns public.restaurant_orders language plpgsql security definer set search_path = public as $$
declare v_order public.restaurant_orders; v_coupon public.restaurant_coupons;
  v_phone text := public.restaurant_normalize_phone(p_customer_phone); v_discount numeric(12,2);
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Carrinho vazio'; end if;
  if p_marketing_opt_in and v_phone is null then raise exception 'Informe um WhatsApp válido para receber ofertas'; end if;
  -- O total vem do catálogo no banco, nunca do valor enviado pelo navegador.
  v_order := public.restaurant_submit_order(p_restaurant_slug, p_channel, p_table_code,
    p_customer_name, coalesce(v_phone,p_customer_phone), p_delivery_address, null, null, p_items);
  if nullif(trim(p_coupon_code),'') is not null then
    select * into v_coupon from public.restaurant_coupons
      where restaurant_id = v_order.restaurant_id and code = upper(trim(p_coupon_code)) for update;
    if not found then raise exception 'Cupom inválido'; end if;
    if not v_coupon.active or (v_coupon.expires_at is not null and v_coupon.expires_at <= now())
      or (v_coupon.usage_limit is not null and v_coupon.used_count >= v_coupon.usage_limit) then
      raise exception 'Cupom expirado, pausado ou esgotado';
    end if;
    if v_coupon.customer_phone is not null and v_coupon.customer_phone is distinct from v_phone then
      raise exception 'Este cupom pertence a outro cliente';
    end if;
    if v_order.subtotal < v_coupon.minimum_total then raise exception 'O pedido não atingiu o valor mínimo do cupom'; end if;
    v_discount := least(v_order.subtotal, case when v_coupon.kind = 'percent'
      then round(v_order.subtotal*v_coupon.amount/100,2) else v_coupon.amount end);
    update public.restaurant_coupons set used_count = used_count + 1 where id = v_coupon.id;
    update public.restaurant_orders set coupon_id = v_coupon.id, discount = v_discount,
      total = subtotal + delivery_fee - v_discount where id = v_order.id returning * into v_order;
  end if;
  update public.restaurant_orders set marketing_opt_in = coalesce(p_marketing_opt_in,false)
    where id = v_order.id returning * into v_order;
  if v_phone is not null then
    insert into public.restaurant_marketing_customers(restaurant_id,phone,name,opted_in,consent_at)
      values(v_order.restaurant_id,v_phone,coalesce(p_customer_name,''),coalesce(p_marketing_opt_in,false),case when p_marketing_opt_in then now() end)
    on conflict(restaurant_id,phone) do update set
      name = case when excluded.name <> '' then excluded.name else restaurant_marketing_customers.name end,
      opted_in = restaurant_marketing_customers.opted_in or excluded.opted_in,
      consent_at = case when excluded.opted_in then now() else restaurant_marketing_customers.consent_at end;
  end if;
  return v_order;
end;
$$;
revoke all on function public.restaurant_marketing_submit_order(text,text,jsonb,text,text,text,jsonb,text,boolean) from public;
grant execute on function public.restaurant_marketing_submit_order(text,text,jsonb,text,text,text,jsonb,text,boolean) to anon,authenticated;

create or replace function public.restaurant_credit_loyalty()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_phone text; v_settings public.restaurant_loyalty_settings; v_stamps integer; v_coupon uuid;
begin
  if new.status <> 'delivered' or old.status = 'delivered' then return new; end if;
  v_phone := public.restaurant_normalize_phone(new.customer_phone);
  if v_phone is null then return new; end if;
  insert into public.restaurant_loyalty_events(order_id,restaurant_id,phone)
    values(new.id,new.restaurant_id,v_phone) on conflict(order_id) do nothing;
  if not found then return new; end if;
  insert into public.restaurant_marketing_customers(restaurant_id,phone,name)
    values(new.restaurant_id,v_phone,coalesce(new.customer_name,'')) on conflict do nothing;
  -- O lock do cliente serializa entregas simultâneas e evita prêmios duplicados.
  perform 1 from public.restaurant_marketing_customers where restaurant_id = new.restaurant_id and phone = v_phone for update;
  update public.restaurant_marketing_customers set delivered_orders = delivered_orders + 1,
    last_order_at = now() where restaurant_id = new.restaurant_id and phone = v_phone;
  select * into v_settings from public.restaurant_loyalty_settings where restaurant_id = new.restaurant_id;
  if not found or not v_settings.enabled or new.total <= 0 then return new; end if;
  update public.restaurant_marketing_customers set stamps = stamps + 1
    where restaurant_id = new.restaurant_id and phone = v_phone returning stamps into v_stamps;
  if v_stamps >= v_settings.target_orders then
    insert into public.restaurant_coupons(restaurant_id,code,kind,amount,usage_limit,customer_phone)
      values(new.restaurant_id,'FID-'||upper(replace(gen_random_uuid()::text,'-','')),'fixed',v_settings.reward_amount,1,v_phone)
      returning id into v_coupon;
    update public.restaurant_marketing_customers set stamps = stamps - v_settings.target_orders
      where restaurant_id = new.restaurant_id and phone = v_phone;
    update public.restaurant_loyalty_events set reward_coupon_id = v_coupon where order_id = new.id;
  end if;
  return new;
end;
$$;
create trigger restaurant_credit_loyalty after update of status on public.restaurant_orders
  for each row execute function public.restaurant_credit_loyalty();
revoke all on function public.restaurant_credit_loyalty() from public,anon,authenticated;

create or replace function public.restaurant_campaign_open(p_campaign_id uuid,p_phone text)
returns void language plpgsql security definer set search_path = public as $$
declare v_campaign public.restaurant_campaigns;
begin
  select * into v_campaign from public.restaurant_campaigns where id = p_campaign_id;
  if not found or not public.restaurant_is_staff(v_campaign.restaurant_id) then raise exception 'Campanha indisponível'; end if;
  if not exists(select 1 from public.restaurant_marketing_customers
    where restaurant_id = v_campaign.restaurant_id and phone = p_phone and opted_in) then
    raise exception 'Cliente não autorizou campanhas';
  end if;
  insert into public.restaurant_campaign_opens(campaign_id,restaurant_id,phone)
    values(p_campaign_id,v_campaign.restaurant_id,p_phone)
    on conflict(campaign_id,phone) do update set opened_at = now();
end;
$$;
revoke all on function public.restaurant_campaign_open(uuid,text) from public,anon;
grant execute on function public.restaurant_campaign_open(uuid,text) to authenticated;

-- Prévia sem reserva de uso; a confirmação revalida tudo na transação do pedido.
create or replace function public.restaurant_marketing_quote(p_restaurant_slug text,p_items jsonb,p_customer_phone text,p_coupon_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_restaurant uuid; v_coupon public.restaurant_coupons; v_item jsonb; v_product public.restaurant_products;
  v_addon jsonb; v_price numeric; v_subtotal numeric := 0; v_discount numeric; v_quantity integer;
begin
  select id into v_restaurant from public.restaurant_restaurants where slug=p_restaurant_slug and is_open;
  if not found then raise exception 'Restaurante indisponível'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Carrinho vazio'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity is null or v_quantity < 1 then raise exception 'Quantidade inválida'; end if;
    select * into v_product from public.restaurant_products where id=(v_item->>'product_id')::uuid and restaurant_id=v_restaurant and is_available;
    if not found then raise exception 'Produto indisponível'; end if;
    v_subtotal := v_subtotal + v_product.price*v_quantity;
    for v_addon in select * from jsonb_array_elements(coalesce(v_item->'addon_ids','[]'::jsonb)) loop
      select a.price into v_price from public.restaurant_addons a
        join public.restaurant_product_addon_groups pg on pg.addon_group_id=a.group_id
        where a.id=(v_addon #>> '{}')::uuid and pg.product_id=v_product.id and a.is_available;
      if not found then raise exception 'Adicional inválido'; end if;
      v_subtotal := v_subtotal + v_price*v_quantity;
    end loop;
  end loop;
  select * into v_coupon from public.restaurant_coupons where restaurant_id=v_restaurant and code=upper(trim(p_coupon_code));
  if not found then raise exception 'Cupom inválido'; end if;
  if not v_coupon.active or (v_coupon.expires_at is not null and v_coupon.expires_at<=now())
    or (v_coupon.usage_limit is not null and v_coupon.used_count>=v_coupon.usage_limit) then raise exception 'Cupom expirado, pausado ou esgotado'; end if;
  if v_coupon.customer_phone is not null and v_coupon.customer_phone is distinct from public.restaurant_normalize_phone(p_customer_phone) then raise exception 'Este cupom pertence a outro cliente'; end if;
  if v_subtotal<v_coupon.minimum_total then raise exception 'O pedido não atingiu o valor mínimo do cupom'; end if;
  v_discount := least(v_subtotal,case when v_coupon.kind='percent' then round(v_subtotal*v_coupon.amount/100,2) else v_coupon.amount end);
  return jsonb_build_object('subtotal',v_subtotal,'discount',v_discount,'total',v_subtotal-v_discount);
end;
$$;
revoke all on function public.restaurant_marketing_quote(text,jsonb,text,text) from public;
grant execute on function public.restaurant_marketing_quote(text,jsonb,text,text) to anon,authenticated;
