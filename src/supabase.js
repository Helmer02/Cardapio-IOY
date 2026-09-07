const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
const sessionKey = 'fast-burg-session';
export const configured = Boolean(url && key);
function headers(token) { return { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json' }; }
async function request(path, options = {}, token) { if (!configured) throw new Error('Supabase ainda não foi configurado.'); const response = await fetch(`${url}${path}`, { ...options, headers: { ...headers(token), ...(options.headers || {}) } }); const body = await response.json().catch(() => null); if (!response.ok) throw new Error(body?.msg || body?.message || 'Não foi possível concluir a operação.'); return body; }
export function getSession() { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } }
export function saveSession(session) { localStorage.setItem(sessionKey, JSON.stringify(session)); }
export function signOut() { localStorage.removeItem(sessionKey); }
export async function signUpAccount({ name, email, password }) { const data = await request('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email, password, data: { full_name: name } }) }); if (data.session) saveSession(data.session); return data; }
export async function signInAccount({ email, password }) { const data = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) }); saveSession(data); return data; }
export async function createRestaurantAccount(data) { const session = getSession(); return request('/rest/v1/rpc/restaurant_create_account', { method: 'POST', body: JSON.stringify(data) }, session?.access_token); }
export async function saveRestaurantOrder(order) { if (!configured || order.items.some(item => !item.product_id || typeof item.product_id !== 'string')) return { offline: true }; return request('/rest/v1/rpc/restaurant_submit_order', { method: 'POST', body: JSON.stringify(order) }); }
export async function fetchPlatformCompanies() { const session = getSession(); if (!session?.access_token) return []; return request('/rest/v1/restaurant_companies?select=id,legal_name,trade_name,status,billing_email,created_at,restaurant_restaurants(name,slug),restaurant_licenses(status,monthly_price,restaurant_plans(name))&order=created_at.desc', {}, session.access_token); }
export async function fetchMyRestaurants() { const session = getSession(); if (!session?.access_token) return []; return request('/rest/v1/restaurant_staff?select=restaurant_id,role,display_name,restaurant_restaurants(name,slug)&is_active=eq.true', {}, session.access_token); }
