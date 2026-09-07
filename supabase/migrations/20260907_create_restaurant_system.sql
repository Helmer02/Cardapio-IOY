-- Fast Burg: banco exclusivo e independente.
-- Execute este arquivo apenas no novo projeto Supabase do Fast Burg.

create extension if not exists pgcrypto;

create table if not exists public.restaurant_restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  phone text,
  address jsonb not null default '{}'::jsonb,
  timezone text not null default 'America/Sao_Paulo',
  is_open boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.restaurant_staff (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'operator' check (role in ('owner', 'manager', 'operator', 'kitchen')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (restaurant_id, user_id)
);

create table if not exists public.restaurant_categories (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  name text not null,
  description text,
  sort_order integer not null default 0,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurant_id, name)
);

create table if not exists public.restaurant_products (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  category_id uuid references public.restaurant_categories(id) on delete set null,
  name text not null,
  description text,
  price numeric(12,2) not null check (price >= 0),
  image_url text,
  icon text,
  label text,
  sort_order integer not null default 0,
  is_available boolean not null default true,
  print_kitchen boolean not null default true,
  print_counter boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.restaurant_addon_groups (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  name text not null,
  min_choices integer not null default 0 check (min_choices >= 0),
  max_choices integer check (max_choices is null or max_choices >= min_choices),
  is_required boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_addons (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.restaurant_addon_groups(id) on delete cascade,
  name text not null,
  price numeric(12,2) not null default 0 check (price >= 0),
  is_available boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_product_addon_groups (
  product_id uuid not null references public.restaurant_products(id) on delete cascade,
  addon_group_id uuid not null references public.restaurant_addon_groups(id) on delete cascade,
  sort_order integer not null default 0,
  primary key (product_id, addon_group_id)
);

create table if not exists public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  code text not null,
  display_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (restaurant_id, code)
);

create table if not exists public.restaurant_printers (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  name text not null,
  connection_type text not null check (connection_type in ('usb', 'network', 'pdf')),
  device_name text,
  network_host text,
  network_port integer default 9100,
  paper_width_mm integer not null default 80 check (paper_width_mm in (58, 80)),
  print_kitchen boolean not null default false,
  print_counter boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint restaurant_printers_has_destination check (device_name is not null or network_host is not null or connection_type = 'pdf')
);

create table if not exists public.restaurant_orders (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete restrict,
  public_code text not null default ('FB' || lpad((floor(random() * 999999))::text, 6, '0')),
  channel text not null check (channel in ('dine_in', 'delivery', 'pickup')),
  status text not null default 'new' check (status in ('new', 'preparing', 'ready', 'delivered', 'cancelled')),
  table_id uuid references public.restaurant_tables(id) on delete set null,
  table_code text,
  customer_name text,
  customer_phone text,
  delivery_address jsonb not null default '{}'::jsonb,
  payment_method text,
  notes text,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  delivery_fee numeric(12,2) not null default 0 check (delivery_fee >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ready_at timestamptz,
  delivered_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (restaurant_id, public_code)
);

create table if not exists public.restaurant_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  product_id uuid references public.restaurant_products(id) on delete set null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  total_price numeric(12,2) not null check (total_price >= 0),
  notes text,
  print_kitchen boolean not null default true,
  print_counter boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_order_item_addons (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references public.restaurant_order_items(id) on delete cascade,
  addon_name text not null,
  price numeric(12,2) not null default 0 check (price >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  previous_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_print_jobs (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  printer_id uuid references public.restaurant_printers(id) on delete set null,
  route text not null check (route in ('kitchen', 'counter')),
  status text not null default 'pending' check (status in ('pending', 'printing', 'printed', 'failed')),
  copies integer not null default 1 check (copies > 0),
  error_message text,
  printed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.restaurant_whatsapp_messages (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurant_restaurants(id) on delete cascade,
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  recipient_phone text not null,
  template_key text not null,
  content text not null,
  status text not null default 'draft' check (status in ('draft', 'opened', 'sent', 'failed')),
  provider_message_id text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists restaurant_orders_restaurant_status_created_idx on public.restaurant_orders(restaurant_id, status, created_at desc);
create index if not exists restaurant_order_items_order_idx on public.restaurant_order_items(order_id);
create index if not exists restaurant_print_jobs_pending_idx on public.restaurant_print_jobs(restaurant_id, status, created_at);
create index if not exists restaurant_products_catalog_idx on public.restaurant_products(restaurant_id, category_id, is_available, sort_order);

create or replace function public.restaurant_set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

drop trigger if exists restaurant_restaurants_updated_at on public.restaurant_restaurants;
create trigger restaurant_restaurants_updated_at before update on public.restaurant_restaurants for each row execute function public.restaurant_set_updated_at();
drop trigger if exists restaurant_categories_updated_at on public.restaurant_categories;
create trigger restaurant_categories_updated_at before update on public.restaurant_categories for each row execute function public.restaurant_set_updated_at();
drop trigger if exists restaurant_products_updated_at on public.restaurant_products;
create trigger restaurant_products_updated_at before update on public.restaurant_products for each row execute function public.restaurant_set_updated_at();
drop trigger if exists restaurant_orders_updated_at on public.restaurant_orders;
create trigger restaurant_orders_updated_at before update on public.restaurant_orders for each row execute function public.restaurant_set_updated_at();
drop trigger if exists restaurant_print_jobs_updated_at on public.restaurant_print_jobs;
create trigger restaurant_print_jobs_updated_at before update on public.restaurant_print_jobs for each row execute function public.restaurant_set_updated_at();

create or replace function public.restaurant_is_staff(target_restaurant uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.restaurant_staff
    where restaurant_id = target_restaurant and user_id = auth.uid() and is_active
  );
$$;

grant execute on function public.restaurant_is_staff(uuid) to anon, authenticated;

alter table public.restaurant_restaurants enable row level security;
alter table public.restaurant_staff enable row level security;
alter table public.restaurant_categories enable row level security;
alter table public.restaurant_products enable row level security;
alter table public.restaurant_addon_groups enable row level security;
alter table public.restaurant_addons enable row level security;
alter table public.restaurant_product_addon_groups enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.restaurant_printers enable row level security;
alter table public.restaurant_orders enable row level security;
alter table public.restaurant_order_items enable row level security;
alter table public.restaurant_order_item_addons enable row level security;
alter table public.restaurant_order_status_history enable row level security;
alter table public.restaurant_print_jobs enable row level security;
alter table public.restaurant_whatsapp_messages enable row level security;

-- Remove policies from a prior prototype migration, when they exist.
drop policy if exists "restaurant orders: public insert" on public.restaurant_orders;
drop policy if exists "restaurant orders: staff manage" on public.restaurant_orders;

create policy "restaurant public catalog" on public.restaurant_categories for select to anon, authenticated using (is_available);
create policy "restaurant public products" on public.restaurant_products for select to anon, authenticated using (is_available);
create policy "restaurant public addons" on public.restaurant_addons for select to anon, authenticated using (is_available);

-- O cliente cria pedidos somente por restaurant_submit_order(). A função usa
-- preços do banco e impede inserções diretas com valores adulterados.

-- Equipe autenticada acessa apenas os registros da própria loja.
create policy "restaurant staff restaurants" on public.restaurant_restaurants for select to authenticated using (public.restaurant_is_staff(id));
create policy "restaurant staff staff" on public.restaurant_staff for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff categories" on public.restaurant_categories for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff products" on public.restaurant_products for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff addon groups" on public.restaurant_addon_groups for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff addons" on public.restaurant_addons for all to authenticated using (exists (select 1 from public.restaurant_addon_groups g where g.id=group_id and public.restaurant_is_staff(g.restaurant_id))) with check (exists (select 1 from public.restaurant_addon_groups g where g.id=group_id and public.restaurant_is_staff(g.restaurant_id)));
create policy "restaurant staff tables" on public.restaurant_tables for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff printers" on public.restaurant_printers for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff orders" on public.restaurant_orders for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff print jobs" on public.restaurant_print_jobs for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));
create policy "restaurant staff whatsapp" on public.restaurant_whatsapp_messages for all to authenticated using (public.restaurant_is_staff(restaurant_id)) with check (public.restaurant_is_staff(restaurant_id));

-- Child rows inherit permission from the restaurant that owns the order/product/group.
create policy "restaurant staff order items" on public.restaurant_order_items for all to authenticated using (exists (select 1 from public.restaurant_orders o where o.id=order_id and public.restaurant_is_staff(o.restaurant_id))) with check (exists (select 1 from public.restaurant_orders o where o.id=order_id and public.restaurant_is_staff(o.restaurant_id)));
create policy "restaurant staff item addons" on public.restaurant_order_item_addons for all to authenticated using (exists (select 1 from public.restaurant_order_items i join public.restaurant_orders o on o.id=i.order_id where i.id=order_item_id and public.restaurant_is_staff(o.restaurant_id))) with check (exists (select 1 from public.restaurant_order_items i join public.restaurant_orders o on o.id=i.order_id where i.id=order_item_id and public.restaurant_is_staff(o.restaurant_id)));
create policy "restaurant staff product addon groups" on public.restaurant_product_addon_groups for all to authenticated using (exists (select 1 from public.restaurant_products p where p.id=product_id and public.restaurant_is_staff(p.restaurant_id))) with check (exists (select 1 from public.restaurant_products p where p.id=product_id and public.restaurant_is_staff(p.restaurant_id)));
create policy "restaurant staff status history" on public.restaurant_order_status_history for all to authenticated using (exists (select 1 from public.restaurant_orders o where o.id=order_id and public.restaurant_is_staff(o.restaurant_id))) with check (exists (select 1 from public.restaurant_orders o where o.id=order_id and public.restaurant_is_staff(o.restaurant_id)));

-- Canal público seguro para pedidos: o preço é sempre recalculado com o
-- cardápio do banco e pedido/itens/adicionais são criados numa transação só.
create or replace function public.restaurant_submit_order(
  p_restaurant_slug text,
  p_channel text,
  p_table_code text default null,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_delivery_address jsonb default '{}'::jsonb,
  p_payment_method text default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.restaurant_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant public.restaurant_restaurants;
  v_order public.restaurant_orders;
  v_item jsonb;
  v_product public.restaurant_products;
  v_order_item public.restaurant_order_items;
  v_addon jsonb;
  v_addon_row public.restaurant_addons;
  v_quantity integer;
  v_item_total numeric(12,2);
  v_subtotal numeric(12,2) := 0;
begin
  if p_channel not in ('dine_in', 'delivery', 'pickup') then
    raise exception 'Canal de pedido inválido';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'O pedido deve conter ao menos um item';
  end if;

  select * into v_restaurant from public.restaurant_restaurants
  where slug = p_restaurant_slug and is_open;
  if not found then raise exception 'Restaurante indisponível'; end if;
  if p_channel = 'dine_in' and coalesce(trim(p_table_code), '') = '' then
    raise exception 'Mesa obrigatória para consumo no local';
  end if;
  if p_channel = 'delivery' and (coalesce(trim(p_customer_name), '') = '' or coalesce(trim(p_customer_phone), '') = '') then
    raise exception 'Nome e telefone obrigatórios para delivery';
  end if;

  insert into public.restaurant_orders (restaurant_id, channel, table_code, customer_name, customer_phone, delivery_address, payment_method, notes)
  values (v_restaurant.id, p_channel, p_table_code, p_customer_name, p_customer_phone, coalesce(p_delivery_address, '{}'::jsonb), p_payment_method, p_notes)
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_quantity := coalesce((v_item->>'quantity')::integer, 0);
    if v_quantity < 1 then raise exception 'Quantidade inválida'; end if;
    select * into v_product from public.restaurant_products
      where id = (v_item->>'product_id')::uuid and restaurant_id = v_restaurant.id and is_available;
    if not found then raise exception 'Produto indisponível'; end if;
    v_item_total := v_product.price * v_quantity;
    insert into public.restaurant_order_items (order_id, product_id, product_name, quantity, unit_price, total_price, notes, print_kitchen, print_counter)
    values (v_order.id, v_product.id, v_product.name, v_quantity, v_product.price, v_item_total, v_item->>'notes', v_product.print_kitchen, v_product.print_counter)
    returning * into v_order_item;

    for v_addon in select * from jsonb_array_elements(coalesce(v_item->'addon_ids', '[]'::jsonb)) loop
      select a.* into v_addon_row from public.restaurant_addons a
      join public.restaurant_addon_groups g on g.id = a.group_id
      join public.restaurant_product_addon_groups pg on pg.addon_group_id = g.id
      where a.id = (trim(both '"' from v_addon::text))::uuid and pg.product_id = v_product.id and a.is_available;
      if not found then raise exception 'Adicional inválido para o produto'; end if;
      insert into public.restaurant_order_item_addons (order_item_id, addon_name, price)
      values (v_order_item.id, v_addon_row.name, v_addon_row.price * v_quantity);
      update public.restaurant_order_items set total_price = total_price + (v_addon_row.price * v_quantity) where id = v_order_item.id;
      v_item_total := v_item_total + (v_addon_row.price * v_quantity);
    end loop;
    v_subtotal := v_subtotal + v_item_total;
  end loop;

  update public.restaurant_orders set subtotal = v_subtotal, total = v_subtotal where id = v_order.id returning * into v_order;
  insert into public.restaurant_order_status_history (order_id, previous_status, new_status) values (v_order.id, null, 'new');
  return v_order;
end;
$$;

grant execute on function public.restaurant_submit_order(text, text, text, text, text, jsonb, text, text, jsonb) to anon, authenticated;

-- Dados iniciais da Fast Burg; não duplica se a migração for executada novamente.
insert into public.restaurant_restaurants (name, slug, phone)
values ('Fast Burg', 'fast-burg', '(11) 99999-9999')
on conflict (slug) do nothing;
