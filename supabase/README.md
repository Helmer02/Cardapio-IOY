# Banco independente do Fast Burg

Este módulo deve ser aplicado em um **novo projeto Supabase**, exclusivo para o Fast Burg. Não reutilize o projeto, URL, chaves ou tabelas de outro sistema.

Após criar o novo projeto, execute as migrações em ordem no **SQL Editor** dele:

1. `migrations/20260907_create_restaurant_system.sql`
2. `migrations/20260908_add_platform_accounts.sql`

Ela cria as tabelas do sistema com prefixo `restaurant_`. O banco novo começa sem qualquer dependência do sistema anterior.

## O que a migração cria

- loja e usuários da equipe;
- categorias, produtos, grupos de adicionais e mesas;
- impressoras e fila de impressão (cozinha/balcão);
- pedidos, itens, adicionais e histórico de status;
- rascunhos e histórico de mensagens de WhatsApp;
- políticas RLS por restaurante e uma função segura para registrar pedidos públicos.

## Primeiro acesso de gestor

1. Crie o usuário normalmente em **Authentication > Users**.
2. Copie o UUID dele.
3. No SQL Editor, substitua os valores e execute:

```sql
insert into public.restaurant_staff (restaurant_id, user_id, display_name, role)
select id, 'UUID_DO_USUARIO'::uuid, 'Nome do gestor', 'owner'
from public.restaurant_restaurants
where slug = 'fast-burg';
```

O painel poderá então usar esse usuário autenticado para visualizar e gerenciar os dados da loja.

## Seu acesso de plataforma

Depois de criar seu usuário em **Authentication > Users**, marque-o como administrador global. Substitua o UUID e execute:

```sql
insert into public.restaurant_platform_admins (user_id, display_name)
values ('UUID_DO_SEU_USUARIO'::uuid, 'Administrador Fast Burg')
on conflict (user_id) do update set display_name = excluded.display_name;
```

Esse acesso permite visualizar empresas, restaurantes, licenças e cobranças na gestão da plataforma.

## Entradas do sistema

Não compartilhe as rotas internas com clientes finais:

- `/?modo=vendas` - landing page comercial;
- `/?modo=cadastro` - cadastro de uma conta de restaurante/empresa;
- `/?modo=restaurante` - login do gestor do restaurante;
- `/?modo=gestao` - login da gestão global da plataforma;
- `/` - cardápio/pedido para o cliente final.
