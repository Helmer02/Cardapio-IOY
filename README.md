# IOY Sistemas

Plataforma de cardápio digital e operação para restaurantes: pedidos no salão, delivery, painel da unidade e gestão multiempresa.

## Entradas

- `/` - home comercial e acesso do proprietário;
- `/?loja=slug-do-restaurante` - cardápio público de uma unidade; este é o link que o proprietário compartilha;
- `/?modo=vendas` - landing comercial;
- `/?modo=cadastro` - onboarding de uma conta que você liberar;
- `/?modo=restaurante` - login do gestor da unidade;
- `/?modo=gestao` - administração global da plataforma.

## Desenvolvimento

```bash
npm install
npm run dev
```

Copie `.env.example` para `.env.local` e informe somente a URL e a chave publishable do projeto Supabase exclusivo da IOY Sistemas.

## Banco de dados

Execute as migrações em ordem no SQL Editor:

1. `supabase/migrations/20260907_create_restaurant_system.sql`
2. `supabase/migrations/20260908_add_platform_accounts.sql`
3. `supabase/migrations/20260908_add_public_restaurant_menu.sql`
4. `supabase/migrations/20260909_fix_public_menu_and_orders.sql`
5. `supabase/migrations/20260910_persist_order_status.sql`
6. `supabase/migrations/20260911_restaurant_marketing.sql`
7. `supabase/migrations/20260912_product_promotions.sql`

As permissões e o fluxo para criar o administrador global estão em [supabase/README.md](supabase/README.md).

## Estado atual da operação

### Produtos e promoções

O editor mostra progresso ao salvar, confirma o sucesso no painel e mantém o formulário preenchido quando há erro. O campo **Preço promocional** é opcional: ao preenchê-lo, o preço de venda fica riscado no cardápio; apagar o campo encerra a promoção. A migração `20260912_product_promotions.sql` é necessária para esta versão do catálogo. O banco mantém `price` como valor efetivamente cobrado e `regular_price` como referência anterior; pedidos e cupons usam o preço reduzido.

### Marketing do restaurante

A aba **Marketing** inclui cupons, fidelidade e campanhas individuais de WhatsApp. Aplique a migração `20260911_restaurant_marketing.sql` antes de usar esta versão: o checkout agora chama a função de pedidos com marketing.

- Cupons percentuais ou em reais, mínimo de compra, validade, limite de usos e pausa. A prévia não reserva uso; a confirmação valida e grava desconto/total na mesma transação. Um cupom por pedido; o uso é consumido na confirmação.
- Fidelidade configurável por loja: pedidos entregues com total positivo e telefone válido geram selos quando o programa está ativo. Ao atingir a meta, é emitido um cupom de uso único vinculado ao telefone. O painel mostra os códigos para o restaurante informar ao cliente. Não há consulta pública de saldo por telefone.
- Campanhas salvas com mensagem e público (autorizados, inativos há 30 dias ou recorrentes). O operador abre e confirma cada envio no WhatsApp. O histórico registra **abertura da conversa**, não envio, entrega ou leitura. Não há disparo automático nem integração de API do WhatsApp nesta versão.
- O cliente pode autorizar ofertas no carrinho; o restaurante pode retirar contatos da lista. A fidelidade não exige consentimento para campanhas.
- Testes: `npm run test:marketing` usa PostgreSQL local em memória (PGlite), cobrindo regras de desconto, rollback, recompensas e permissões. O banco real não é alterado pelos testes.

### Gestão de pedidos — atualização de 10/09/2026

Após as migrações anteriores, aplique `supabase/migrations/20260910_persist_order_status.sql` no SQL Editor do projeto Supabase da IOY. Essa etapa é necessária para ativar os botões de mudança de status.

- Filtros de salão, delivery e retirada, com consulta de concluídos/cancelados.
- Sincronização a cada 10 segundos enquanto o painel está visível, além de atualização manual.
- Status confirmado pelo banco, com histórico do atendente e horários de preparo, pronto e entrega na mesma transação.
- Conflitos entre atendentes e falhas de conexão são exibidos sem simular uma gravação bem-sucedida.
- Validação local: `npm run build` e `node work/test-orders.cjs`. O teste usa respostas simuladas; a validação no Supabase exige aplicar a migração e usar uma conta de equipe.

- O fluxo visual de pedido, carrinho, produção, impressão de teste, WhatsApp e gestão está pronto.
- A gestão de acesso usa Supabase Auth e bloqueia o painel de restaurante para usuários sem vínculo de equipe.
- O pedido só é confirmado como operacional quando os produtos locais estiverem vinculados aos UUIDs do catálogo no Supabase. Enquanto isso, o app apresenta explicitamente o modo de demonstração e não finge enviar o pedido.
- A impressão direta em Elgin USB exige o agente local de impressão; hoje o painel oferece teste via PDF/navegador.
