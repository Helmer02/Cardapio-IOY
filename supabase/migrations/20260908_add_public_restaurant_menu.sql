-- Cardápio público multiempresa. A consulta é feita pelo slug da unidade e
-- devolve apenas dados que podem ser exibidos aos clientes.
create or replace function public.restaurant_public_menu(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant public.restaurant_restaurants;
  v_products jsonb;
begin
  select * into v_restaurant
  from public.restaurant_restaurants
  where slug = lower(trim(p_slug)) and is_open;

  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'description', p.description,
    'price', p.price,
    'image_url', p.image_url,
    'icon', coalesce(p.icon, '🍔'),
    'label', p.label,
    'category', coalesce(c.name, 'Cardápio'),
    'available', p.is_available
  ) order by c.sort_order nulls last, p.sort_order, p.name), '[]'::jsonb)
  into v_products
  from public.restaurant_products p
  left join public.restaurant_categories c on c.id = p.category_id
  where p.restaurant_id = v_restaurant.id and p.is_available;

  return jsonb_build_object(
    'restaurant', jsonb_build_object('id', v_restaurant.id, 'name', v_restaurant.name, 'slug', v_restaurant.slug),
    'products', v_products
  );
end;
$$;

grant execute on function public.restaurant_public_menu(text) to anon, authenticated;
