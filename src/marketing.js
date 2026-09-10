import { marketingList, marketingWrite, recordCampaignOpen } from './supabase.js';
import './marketing.css';

const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const money = value => new Intl.NumberFormat('pt-BR', { style:'currency', currency:'BRL' }).format(value);
let model = { restaurantId:null, tab:'coupons', loading:false, busy:false, error:'', notice:'', coupons:[], customers:[], campaigns:[], opens:[], settings:{} };

export function campaignAudience(customers, audience, now = Date.now()) {
  return customers.filter(customer => customer.opted_in && (audience === 'all' || (audience === 'loyal' && customer.delivered_orders >= 3) || (audience === 'inactive' && customer.last_order_at && now - new Date(customer.last_order_at).getTime() >= 30*86400000)));
}
export function campaignMessage(template, customer, link) {
  return template.replace(/\{nome\}/g, customer.name || 'cliente').replace(/\{link\}/g, link);
}

export async function loadMarketing(restaurant, render) {
  if (model.loading) return;
  if (model.restaurantId !== restaurant.id) model = { restaurantId:restaurant.id, tab:'coupons', loading:false, busy:false, error:'', notice:'', coupons:[], customers:[], campaigns:[], opens:[], settings:{} };
  model.loading=true; model.error=''; render();
  try {
    const [coupons,customers,campaigns,opens,settings] = await Promise.all([
      'restaurant_coupons','restaurant_marketing_customers','restaurant_campaigns','restaurant_campaign_opens','restaurant_loyalty_settings',
    ].map(table=>marketingList(table,restaurant.id)));
    Object.assign(model,{coupons,customers,campaigns,opens,settings:settings[0] || {enabled:false,target_orders:10,reward_amount:10}});
  } catch (error) { model.error='Não foi possível carregar o marketing. '+error.message; }
  finally { model.loading=false; render(); }
}

export function marketingPanel() {
  return `<section class="marketing"><div class="marketing-intro"><div><span class="eyebrow">CLIENTES QUE VOLTAM</span><h2>Uma boa oferta começa uma nova visita.</h2><p>Cupons, recompensas e conversas para aproximar seu restaurante dos clientes.</p></div><button class="marketing-secondary" id="marketing-refresh" ${model.loading || model.busy?'disabled':''}>Atualizar</button></div>
    <div class="marketing-stats"><article><small>Cupons disponíveis</small><b>${model.coupons.filter(available).length}</b></article><article><small>Clientes com pedidos</small><b>${model.customers.length}</b></article><article><small>Autorizaram campanhas</small><b>${model.customers.filter(c=>c.opted_in).length}</b></article></div>
    <nav class="marketing-tabs" aria-label="Marketing">${[['coupons','Cupons'],['loyalty','Fidelidade'],['campaigns','WhatsApp']].map(([key,label])=>`<button data-marketing-tab="${key}" aria-pressed="${model.tab===key}">${label}</button>`).join('')}</nav>
    ${model.error?`<p class="form-error" role="alert">${escape(model.error)}</p>`:''}${model.notice?`<p class="account-notice" role="status">${escape(model.notice)}</p>`:''}
    ${model.loading?'<p role="status">Carregando dados do restaurante...</p>':model.error?'<p>Use Atualizar para tentar novamente.</p>':model.tab==='coupons'?couponsPanel():model.tab==='loyalty'?loyaltyPanel():campaignsPanel()}</section>`;
}
function available(coupon) { return coupon.active && (!coupon.expires_at || new Date(coupon.expires_at)>new Date()) && (!coupon.usage_limit || coupon.used_count<coupon.usage_limit); }
function couponsPanel() {
  return `<div class="marketing-grid"><form id="coupon-form" class="marketing-card"><h3>Criar cupom</h3><label>Código<input name="code" required pattern="[A-Za-z0-9_-]{3,40}" maxlength="40" placeholder="VOLTE10"></label><div class="marketing-pair"><label>Tipo<select name="kind"><option value="percent">Percentual (%)</option><option value="fixed">Valor em reais (R$)</option></select></label><label>Desconto<input name="amount" type="number" min="0.01" step="0.01" required placeholder="10"></label></div><label>Pedido mínimo (R$)<input name="minimum_total" type="number" min="0" step="0.01" value="0" required></label><div class="marketing-pair"><label>Validade (opcional)<input name="expires_at" type="datetime-local"></label><label>Limite de usos (opcional)<input name="usage_limit" type="number" min="1" step="1" placeholder="Sem limite"></label></div><small>Um cupom por pedido. O desconto é calculado sobre os produtos e nunca supera o subtotal.</small><button class="primary" ${model.busy?'disabled':''}>Salvar cupom</button></form><div class="marketing-card"><h3>Cupons do restaurante</h3>${model.coupons.length?model.coupons.map(c=>`<article class="marketing-row"><div><b>${escape(c.code)}</b><p>${c.kind==='percent'?`${Number(c.amount)}%`:money(c.amount)} de desconto · mínimo ${money(c.minimum_total)}</p><small>${c.used_count}${c.usage_limit?` / ${c.usage_limit}`:''} usos · ${available(c)?'Disponível':'Indisponível'}${c.expires_at?` · até ${escape(new Date(c.expires_at).toLocaleString('pt-BR'))}`:''}${c.customer_phone?` · recompensa de ${escape(c.customer_phone)}`:''}</small></div><button class="marketing-secondary" data-coupon-toggle="${c.id}" ${model.busy?'disabled':''}>${c.active?'Pausar':'Ativar'}</button></article>`).join(''):'<p class="marketing-empty">Crie seu primeiro cupom para incentivar uma nova compra.</p>'}</div></div>`;
}
function loyaltyPanel() {
  const settings=model.settings;
  return `<div class="marketing-grid"><form id="loyalty-form" class="marketing-card"><h3>Recompense quem volta</h3><label class="marketing-check"><input type="checkbox" name="enabled" ${settings.enabled?'checked':''}> Ativar fidelidade</label><label>Pedidos para ganhar uma recompensa<input name="target_orders" type="number" min="2" max="100" step="1" required value="${settings.target_orders}"></label><label>Valor do cupom de recompensa (R$)<input name="reward_amount" type="number" min="0.01" step="0.01" required value="${settings.reward_amount}"></label><p>Cada pedido entregue com valor maior que zero e WhatsApp informado vale um selo. Ao completar a meta, o cliente ganha um cupom de uso único, vinculado ao telefone.</p><small>Conta a partir da ativação. Pausar mantém os selos. Uma nova meta será aplicada na próxima entrega; recompensas já emitidas continuam válidas.</small><button class="primary" ${model.busy?'disabled':''}>Salvar programa</button></form><div class="marketing-card"><h3>Clientes e recompensas</h3>${model.customers.length?model.customers.map(c=>`<article class="marketing-row"><div><b>${escape(c.name || 'Cliente')}</b><p>${escape(c.phone)} · ${c.stamps} selos · ${c.delivered_orders} pedidos entregues</p><small>${c.opted_in?'Campanhas autorizadas':'Sem autorização para campanhas'}</small>${model.coupons.filter(coupon=>coupon.customer_phone===c.phone && available(coupon)).map(coupon=>`<p class="reward-code">${escape(coupon.code)} · ${money(coupon.amount)}</p>`).join('')}</div>${c.opted_in?`<button class="marketing-secondary" data-optout="${escape(c.phone)}" ${model.busy?'disabled':''}>Retirar das campanhas</button>`:''}</article>`).join(''):'<p class="marketing-empty">Os clientes aparecem quando fazem pedidos com WhatsApp informado.</p>'}</div></div>`;
}
function campaignsPanel() {
  return `<div class="marketing-grid"><form id="campaign-form" class="marketing-card"><h3>Preparar campanha</h3><label>Nome interno<input name="name" required maxlength="100" placeholder="Oferta do fim de semana"></label><label>Público<select name="audience"><option value="all">Todos que autorizaram</option><option value="inactive">Sem pedir há 30 dias</option><option value="loyal">Recorrentes (3 ou mais pedidos)</option></select></label><label>Mensagem<textarea name="message" rows="6" maxlength="2000" required placeholder="Olá, {nome}! Use VOLTE10 na próxima compra. Peça aqui: {link}"></textarea></label><small>Use {nome} para o nome do cliente e {link} para o cardápio. Inclua o código de um cupom disponível, se desejar.</small><p>O envio é individual e confirmado por você no WhatsApp. A abertura da conversa não confirma entrega ou leitura.</p><button class="primary" ${model.busy?'disabled':''}>Salvar campanha</button></form><div class="marketing-card"><h3>Campanhas salvas</h3>${model.campaigns.length?model.campaigns.map(campaign=>{const customers=campaignAudience(model.customers,campaign.audience);return `<details class="campaign-item"><summary>${escape(campaign.name)} <small>· ${customers.length} contatos</small></summary><p class="campaign-message">${escape(campaign.message)}</p><small>Confira a mensagem no WhatsApp antes de enviar. Para sair da lista, o cliente pode pedir ao restaurante.</small>${customers.length?customers.map(customer=>`<div class="marketing-row"><div><b>${escape(customer.name || customer.phone)}</b><small>${model.opens.some(o=>o.campaign_id===campaign.id && o.phone===customer.phone)?'Conversa já aberta':'Ainda não aberta'}</small></div><button class="marketing-secondary" data-campaign="${campaign.id}" data-recipient="${escape(customer.phone)}" ${model.busy?'disabled':''}>Abrir WhatsApp ↗</button></div>`).join(''):'<p class="marketing-empty">Nenhum cliente autorizado neste público.</p>'}</details>`;}).join(''):'<p class="marketing-empty">Salve a primeira campanha para escolher os contatos e abrir as conversas.</p>'}</div></div>`;
}

export function bindMarketing(restaurant, render) {
  document.querySelector('#marketing-refresh')?.addEventListener('click',()=>loadMarketing(restaurant,render));
  document.querySelectorAll('[data-marketing-tab]').forEach(button=>button.onclick=()=>{model.tab=button.dataset.marketingTab;model.notice='';render();});
  // Preserve form values on errors: only render after a successful save.
  async function save(action, notice) {
    if(model.busy) return;
    model.busy=true;
    document.querySelectorAll('.marketing button').forEach(button=>button.disabled=true);
    try { await action(); model.notice=notice; await loadMarketing(restaurant,render); }
    catch(error) { const panel=document.querySelector('.marketing'); panel?.querySelector('[data-save-error]')?.remove(); panel?.insertAdjacentHTML('afterbegin',`<p class="form-error" data-save-error role="alert">${escape(error.message)}</p>`); }
    finally {model.busy=false;document.querySelectorAll('.marketing button').forEach(button=>button.disabled=false);}
  }
  document.querySelector('#coupon-form')?.addEventListener('submit',event=>{
    event.preventDefault();const form=new FormData(event.currentTarget);
    save(async()=>{
      const amount=Number(form.get('amount')),kind=form.get('kind');
      if(kind==='percent' && amount>100) throw new Error('O percentual deve ser de até 100%.');
      const expires=form.get('expires_at');
      if(expires && new Date(expires)<=new Date()) throw new Error('Escolha uma validade futura.');
      await marketingWrite('restaurant_coupons',restaurant.id,{code:form.get('code').trim().toUpperCase(),kind,amount,minimum_total:Number(form.get('minimum_total')),expires_at:expires?new Date(expires).toISOString():null,usage_limit:form.get('usage_limit')?Number(form.get('usage_limit')):null});
    },'Cupom salvo no restaurante.');
  });
  document.querySelectorAll('[data-coupon-toggle]').forEach(button=>button.onclick=()=>{const coupon=model.coupons.find(c=>c.id===button.dataset.couponToggle);save(()=>marketingWrite('restaurant_coupons',restaurant.id,{active:!coupon.active},`id=eq.${coupon.id}`),'Disponibilidade do cupom atualizada.');});
  document.querySelector('#loyalty-form')?.addEventListener('submit',event=>{event.preventDefault();const form=new FormData(event.currentTarget);save(()=>marketingWrite('restaurant_loyalty_settings',restaurant.id,{enabled:form.has('enabled'),target_orders:Number(form.get('target_orders')),reward_amount:Number(form.get('reward_amount'))}),'Programa de fidelidade salvo.');});
  document.querySelectorAll('[data-optout]').forEach(button=>button.onclick=()=>save(()=>marketingWrite('restaurant_marketing_customers',restaurant.id,{opted_in:false},`phone=eq.${encodeURIComponent(button.dataset.optout)}`),'Cliente retirado das campanhas.'));
  document.querySelector('#campaign-form')?.addEventListener('submit',event=>{event.preventDefault();const form=new FormData(event.currentTarget);save(()=>marketingWrite('restaurant_campaigns',restaurant.id,{name:form.get('name').trim(),message:form.get('message').trim(),audience:form.get('audience')}),'Campanha salva. Abra uma conversa para revisar e enviar.');});
  document.querySelectorAll('[data-campaign]').forEach(button=>button.onclick=()=>{
    if(model.busy) return;
    const campaign=model.campaigns.find(c=>c.id===button.dataset.campaign),customer=model.customers.find(c=>c.phone===button.dataset.recipient);
    if(!customer?.opted_in) return;
    const link=`${location.origin}${location.pathname}?loja=${encodeURIComponent(restaurant.slug)}`;
    const message=campaignMessage(campaign.message,customer,link)+'\n\nSe não quiser receber ofertas, responda SAIR.';
    // Open synchronously to avoid popup blocking; navigate only after validating consent in the database.
    const popup=window.open('about:blank','_blank');
    if(!popup) { model.notice='Permita abrir uma nova aba para acessar o WhatsApp.';render();return; }
    popup.opener=null;
    save(async()=>{try {await recordCampaignOpen(campaign.id,customer.phone);popup.location.href=`https://wa.me/${customer.phone}?text=${encodeURIComponent(message)}`;}catch(error){popup.close();throw error;}},'Conversa aberta. Confirme o envio no WhatsApp.');
  });
}
