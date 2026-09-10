-- Atualização atômica: status, horários e histórico na mesma transação.
create or replace function public.restaurant_change_order_status(
  p_restaurant_id uuid, p_order_id uuid, p_expected_status text, p_new_status text
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_order public.restaurant_orders;
begin
  if not public.restaurant_is_staff(p_restaurant_id) then
    raise exception 'Você não tem acesso aos pedidos desta loja';
  end if;
  select * into v_order from public.restaurant_orders
    where id = p_order_id and restaurant_id = p_restaurant_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;
  if p_expected_status is null or v_order.status <> p_expected_status then
    raise exception 'Este pedido foi atualizado por outro atendente. Atualize o painel.';
  end if;
  if p_new_status is null or not (
    (v_order.status = 'new' and p_new_status = 'preparing') or
    (v_order.status = 'preparing' and p_new_status = 'ready') or
    (v_order.status = 'ready' and p_new_status = 'delivered')
  ) then raise exception 'Mudança de status não permitida'; end if;
  update public.restaurant_orders set status = p_new_status,
    accepted_at = case when p_new_status = 'preparing' then now() else accepted_at end,
    ready_at = case when p_new_status = 'ready' then now() else ready_at end,
    delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
    updated_at = now()
    where id = v_order.id;
  insert into public.restaurant_order_status_history(order_id, previous_status, new_status, changed_by)
    values(v_order.id, v_order.status, p_new_status, auth.uid());
  return jsonb_build_object('id', v_order.id, 'status', p_new_status);
end;
$$;
revoke all on function public.restaurant_change_order_status(uuid, uuid, text, text) from public, anon;
grant execute on function public.restaurant_change_order_status(uuid, uuid, text, text) to authenticated;
