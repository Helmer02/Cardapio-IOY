const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
const sessionKey = 'fast-burg-session';
const pendingAccountKey = 'fast-burg-pending-account';
export const configured = Boolean(url && key);
function headers(token) { return { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json' }; }
async function request(path, options = {}, token) { if (!configured) throw new Error('Supabase ainda não foi configurado.'); const response = await fetch(`${url}${path}`, { ...options, headers: { ...headers(token), ...(options.headers || {}) } }); const body = await response.json().catch(() => null); if (!response.ok) throw new Error(body?.msg || body?.message || 'Não foi possível concluir a operação.'); return body; }
export function getSession() { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } }
export function saveSession(session) { localStorage.setItem(sessionKey, JSON.stringify(session)); }
export function signOut() { localStorage.removeItem(sessionKey); }
export function getPendingAccount() { try { return JSON.parse(localStorage.getItem(pendingAccountKey) || 'null'); } catch { return null; } }
export function savePendingAccount(account) { localStorage.setItem(pendingAccountKey, JSON.stringify(account)); }
export function clearPendingAccount() { localStorage.removeItem(pendingAccountKey); }
export async function signUpAccount({ name, email, password }) { const data = await request('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email, password, data: { full_name: name } }) }); if (data.session) saveSession(data.session); return data; }
export async function signInAccount({ email, password }) { const data = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) }); saveSession(data); return data; }
export async function refreshSession() { const session = getSession(); if (!session?.refresh_token) return null; const data = await request('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: session.refresh_token }) }); saveSession(data); return data; }
export async function createRestaurantAccount(data) { const session = getSession(); return request('/rest/v1/rpc/restaurant_create_account', { method: 'POST', body: JSON.stringify(data) }, session?.access_token); }
export async function saveRestaurantOrder(order) {
  // The public RPC receives `p_items`; older callers used `items`.  Accept both
  // shapes here so a missing property can never prevent the checkout from
  // reaching its intended demo fallback.
  const items = Array.isArray(order?.p_items) ? order.p_items : Array.isArray(order?.items) ? order.items : [];
  if (!configured || !items.length || items.some(item => !item?.product_id || typeof item.product_id !== 'string')) return { offline: true };
  return request('/rest/v1/rpc/restaurant_submit_order', { method: 'POST', body: JSON.stringify({ ...order, p_items: items }) });
}
export async function fetchPublicRestaurantMenu(slug) {
  if (!configured) return null;
  return request('/rest/v1/rpc/restaurant_public_menu', { method: 'POST', body: JSON.stringify({ p_slug: slug }) });
}
export async function fetchPlatformCompanies() { const session = getSession(); if (!session?.access_token) return []; return request('/rest/v1/restaurant_companies?select=id,legal_name,trade_name,status,billing_email,created_at,restaurant_restaurants(name,slug),restaurant_licenses(status,monthly_price,restaurant_plans(name))&order=created_at.desc', {}, session.access_token); }
export async function fetchMyRestaurants() { const session = getSession(); if (!session?.access_token) return []; return request('/rest/v1/restaurant_staff?select=restaurant_id,role,display_name,restaurant_restaurants(name,slug)&is_active=eq.true', {}, session.access_token); }
export async function fetchRestaurantOrders(restaurantId) { const session = getSession(); if (!session?.access_token || !restaurantId) return []; return request('/rest/v1/rpc/restaurant_staff_orders', { method: 'POST', body: JSON.stringify({ p_restaurant_id: restaurantId }) }, session.access_token); }
export async function isPlatformAdmin() { const session = getSession(); if (!session?.access_token) return false; return request('/rest/v1/rpc/restaurant_platform_is_admin', { method: 'POST', body: '{}' }, session.access_token); }
export async function fetchRestaurantProducts(restaurantId) { const session = getSession(); if (!session?.access_token || !restaurantId) return []; return request(`/rest/v1/restaurant_products?restaurant_id=eq.${encodeURIComponent(restaurantId)}&select=id,name,description,price,image_url,icon,label,is_available,print_kitchen,print_counter,sort_order,restaurant_categories(name)&order=sort_order.asc,name.asc`, {}, session.access_token); }
export async function saveRestaurantProduct(restaurantId, id, product) { const session = getSession(); if (!session?.access_token || !restaurantId) throw new Error('Sessão do restaurante não encontrada.'); const body={ name: product.name, description: product.description, price: product.price, image_url: product.imageUrl || null, icon: product.emoji, label: product.tag, is_available: product.available, print_kitchen: product.printKitchen, print_counter: product.printCounter }; const path=id ? `/rest/v1/restaurant_products?id=eq.${encodeURIComponent(id)}` : '/rest/v1/restaurant_products'; const method=id?'PATCH':'POST'; if (!id) Object.assign(body,{restaurant_id:restaurantId}); const rows=await request(path,{method,headers:{Prefer:'return=representation'},body:JSON.stringify(body)},session.access_token); return Array.isArray(rows)?rows[0]:rows; }
