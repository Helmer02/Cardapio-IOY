# Fast Burg

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

Copie `.env.example` para `.env.local` e informe somente a URL e a chave publishable do projeto Supabase exclusivo do Fast Burg.

## Banco de dados

Execute as migrações em ordem no SQL Editor:

1. `supabase/migrations/20260907_create_restaurant_system.sql`
2. `supabase/migrations/20260908_add_platform_accounts.sql`

As permissões e o fluxo para criar o administrador global estão em [supabase/README.md](supabase/README.md).

## Estado atual da operação

- O fluxo visual de pedido, carrinho, produção, impressão de teste, WhatsApp e gestão está pronto.
- A gestão de acesso usa Supabase Auth e bloqueia o painel de restaurante para usuários sem vínculo de equipe.
- O pedido só é confirmado como operacional quando os produtos locais estiverem vinculados aos UUIDs do catálogo no Supabase. Enquanto isso, o app apresenta explicitamente o modo de demonstração e não finge enviar o pedido.
- A impressão direta em Elgin USB exige o agente local de impressão; hoje o painel oferece teste via PDF/navegador.
