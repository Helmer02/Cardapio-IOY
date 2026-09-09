-- Garante que toda loja tenha um cardápio inicial utilizável pelo link público.
-- Também disponibiliza ao painel a consulta detalhada e segura dos pedidos da loja.

create or replace function public.restaurant_seed_default_menu(p_restaurant_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.restaurant_categories (restaurant_id, name, sort_order)
  values
    (p_restaurant_id, 'Burgers', 1),
    (p_restaurant_id, 'Acompanhamentos', 2),
    (p_restaurant_id, 'Bebidas', 3),
    (p_restaurant_id, 'Sobremesas', 4)
  on conflict (restaurant_id, name) do nothing;

  insert into public.restaurant_products (restaurant_id, category_id, name, description, price, icon, label, sort_order, print_kitchen, print_counter)
  select p_restaurant_id, c.id, v.name, v.description, v.price, v.icon, v.label, v.sort_order, v.print_kitchen, v.print_counter
  from (values
    ('Burgers', 'Fast Classic', 'Pão brioche, burger de 160g, queijo e molho da casa.', 27.90::numeric, '🍔', 'Mais pedido', 1, true, true),
    ('Burgers', 'Duplo Smash', 'Dois burgers smash, cheddar cremoso e cebola caramelizada.', 34.90::numeric, '🍔', 'Novo', 2, true, true),
    ('Burgers', 'Chicken Crunch', 'Frango empanado crocante, coleslaw e maionese defumada.', 29.90::numeric, '🍗', 'Crocante', 3, true, true),
    ('Acompanhamentos', 'Batata Fast', 'Batata frita sequinha com páprica e sal da casa.', 16.90::numeric, '🍟', 'Para dividir', 1, true, true),
    ('Acompanhamentos', 'Onion Rings', 'Anéis de cebola empanados com molho especial.', 18.90::numeric, '🧅', '8 unidades', 2, true, true),
    ('Bebidas', 'Coca-Cola lata', 'Coca-Cola gelada 350ml.', 6.50::numeric, '🥤', '350ml', 1, false, true),
    ('Sobremesas', 'Milkshake de Nutella', 'Cremoso milkshake de baunilha com Nutella.', 19.90::numeric, '🥛', '400ml', 1, true, true)
  ) as v(category_name, name, description, price, icon, label, sort_order, print_kitchen, print_counter)
  join public.restaurant_categories c on c.restaurant_id = p_restaurant_id and c.name = v.category_name
  where not exists (
    select 1 from public.restaurant_products p where p.restaurant_id = p_restaurant_id and lower(p.name) = lower(v.name)
  );
end;
$$;

create or replace function public.restaurant_seed_menu_on_create()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.restaurant_seed_default_menu(new.id);
  return new;
end;
$$;

drop trigger if exists restaurant_seed_menu_on_create on public.restaurant_restaurants;
create trigger restaurant_seed_menu_on_create
after insert on public.restaurant_restaurants
for each row execute function public.restaurant_seed_menu_on_create();

-- Corrige todas as lojas criadas antes desta migração que ainda não tinham produtos.
do $$
declare r record;
begin
  for r in select id from public.restaurant_restaurants loop
    perform public.restaurant_seed_default_menu(r.id);
  end loop;
end;
$$;

create or replace function public.restaurant_staff_orders(p_restaurant_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.restaurant_is_staff(p_restaurant_id) then
    raise exception 'Você não tem acesso aos pedidos desta loja';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id,
      'public_code', o.public_code,
      'channel', o.channel,
      'status', o.status,
      'table_code', o.table_code,
      'customer_name', o.customer_name,
      'customer_phone', o.customer_phone,
      'delivery_address', o.delivery_address,
      'total', o.total,
      'created_at', o.created_at,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object('product_name', i.product_name, 'quantity', i.quantity, 'total_price', i.total_price) order by i.created_at)
        from public.restaurant_order_items i where i.order_id = o.id
      ), '[]'::jsonb)
    ) order by o.created_at desc)
    from public.restaurant_orders o
    where o.restaurant_id = p_restaurant_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.restaurant_seed_default_menu(uuid) from public, anon, authenticated;
grant execute on function public.restaurant_staff_orders(uuid) to authenticated;
revoke execute on function public.restaurant_staff_orders(uuid) from public, anon;

-- Inclui a foto configurada pelo restaurante no cardápio público.
create or replace function public.restaurant_public_menu(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_restaurant public.restaurant_restaurants; v_products jsonb;
begin
  select * into v_restaurant from public.restaurant_restaurants where slug = lower(trim(p_slug)) and is_open;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price',p.price,'image_url',p.image_url,'icon',coalesce(p.icon,'🍔'),'label',p.label,'category',coalesce(c.name,'Cardápio'),'available',p.is_available) order by c.sort_order nulls last,p.sort_order,p.name),'[]'::jsonb)
  into v_products from public.restaurant_products p left join public.restaurant_categories c on c.id=p.category_id
  where p.restaurant_id=v_restaurant.id and p.is_available;
  return jsonb_build_object('restaurant',jsonb_build_object('id',v_restaurant.id,'name',v_restaurant.name,'slug',v_restaurant.slug),'products',v_products);
end;
$$;

grant execute on function public.restaurant_public_menu(text) to anon, authenticated;
