-- ═══════════════════════════════════════════════════════════════════════
-- COCKPIT COMERCIAL · banco no Supabase
-- Roda NO MESMO PROJETO do Sistema de Orçamentação (depois do supabase_schema.sql dele).
-- Cole este arquivo inteiro no SQL Editor e execute uma vez. É seguro reexecutar.
--
-- Interligação com o Orçamento:
--   • mesmo login (auth.users) e mesmo cadastro de acesso (tabela usuarios);
--   • mesmo porteiro: pode_acessar() — liberar/bloquear no Orçamento vale aqui na hora;
--   • orçamentos ligados aos clientes do Cockpit pelo CNPJ (view ck_vw_orcamentos).
-- Todas as tabelas do Cockpit usam o prefixo ck_ → nada do Orçamento é alterado.
-- ═══════════════════════════════════════════════════════════════════════

-- 0. Pré-requisito: o schema do Orçamento já precisa existir neste projeto
do $$ begin
  if to_regclass('public.usuarios') is null or to_regprocedure('public.pode_acessar()') is null then
    raise exception 'Rode primeiro o supabase_schema.sql do Sistema de Orçamentação neste mesmo projeto.';
  end if;
end $$;

-- ─────────────────────── BASE COMERCIAL (compartilhada pela equipe) ───────────────────────
create table if not exists ck_grupos (
  id         text primary key,                 -- código do cliente principal do grupo
  nome       text not null,
  criado_em  timestamptz not null default now()
);

create table if not exists ck_clientes (
  id              text primary key,            -- = código do cliente
  codigo          text not null unique,
  documento       text,                        -- CNPJ/CPF só dígitos (liga com clientes.cnpj do Orçamento)
  razao_social    text not null,
  nome_fantasia   text,
  grupo_id        text references ck_grupos(id) on delete set null,
  papel_grupo     text,                        -- PRINCIPAL / DEPENDENTE
  segmento        text,
  graduacao       text,
  situacao        text,
  responsavel     text,
  cidade          text, uf text, endereco text, cep text,
  telefone        text, email text,
  limite_total    numeric(14,2), limite_utilizado numeric(14,2),
  frota_total     numeric(10,0),
  atualizado_em   timestamptz not null default now()
);
create index if not exists ck_clientes_grupo on ck_clientes (grupo_id);
create index if not exists ck_clientes_doc   on ck_clientes (documento);

create table if not exists ck_veiculos (
  id        text primary key,                  -- MARCA_MODELO
  marca     text not null,
  modelo    text not null,
  categoria text
);

create table if not exists ck_vendas (
  id                text primary key,          -- pedido|devolução|tipo|produto|ocorrência (estável entre reimportações)
  pedido            text not null,
  devolucao         text,
  cliente_id        text not null references ck_clientes(id) on delete cascade,
  data              date not null,
  etapa             text,                      -- FECHADA, LIBERADA, BLOQUEADA, IMPRESSA, GRAVADA, DELETADA
  situacao          text,
  tipo              text not null check (tipo in ('VENDA','DEVOLUCAO')),
  valor             numeric(14,2) not null default 0,   -- sempre positivo; o sinal vem do tipo
  qtd               numeric(10,2) not null default 1,
  produto_codigo    text,
  produto_descricao text,
  grupo_produto     text,
  veiculo_id        text references ck_veiculos(id) on delete set null,
  loja              text, loja_uf text, vendedor text,
  importacao_id     text,
  criado_em         timestamptz not null default now()
);
create index if not exists ck_vendas_data    on ck_vendas (data);
create index if not exists ck_vendas_cliente on ck_vendas (cliente_id, data);

create table if not exists ck_frota (
  cliente_id      text not null references ck_clientes(id) on delete cascade,
  veiculo_id      text not null references ck_veiculos(id) on delete cascade,
  quantidade      int  not null check (quantidade > 0),
  data_referencia date not null default current_date,
  fonte           text,
  primary key (cliente_id, veiculo_id)
);

create table if not exists ck_importacoes (
  id          text primary key,
  arquivo     text, tipo text, usuario text,
  status      text not null default 'PROCESSANDO',
  linhas      int, inseridos int, atualizados int, ignorados int,
  periodo     text, erro text,
  criado_por  uuid default auth.uid(),
  criado_em   timestamptz not null default now()
);

-- ─────────────────────── WORKSPACE PESSOAL (cada usuário vê só o seu) ───────────────────────
-- Colunas tipadas para análise + o registro completo em "dados" (o app grava os dois).
do $$
declare t text;
begin
  foreach t in array array['ck_eventos','ck_notas','ck_viagens','ck_oportunidades','ck_interacoes',
                           'ck_apresentacoes','ck_quadros','ck_contatos','ck_swot']
  loop
    execute format('create table if not exists %I (
      id            text primary key,
      dono          uuid not null default auth.uid() references auth.users(id) on delete cascade,
      dados         jsonb not null default ''{}''::jsonb,
      excluido_em   timestamptz,
      atualizado_em timestamptz not null default now()
    )', t);
    execute format('create index if not exists %I on %I (dono)', t || '_dono', t);
  end loop;
end $$;
alter table ck_eventos       add column if not exists titulo text, add column if not exists categoria text, add column if not exists status text,
                             add column if not exists inicio timestamptz, add column if not exists fim timestamptz,
                             add column if not exists cliente_id text, add column if not exists viagem_id text;
alter table ck_notas         add column if not exists titulo text, add column if not exists data date,
                             add column if not exists cliente_id text, add column if not exists viagem_id text;
alter table ck_viagens       add column if not exists titulo text, add column if not exists destino text,
                             add column if not exists inicio date, add column if not exists fim date, add column if not exists status text;
alter table ck_oportunidades add column if not exists titulo text, add column if not exists cliente_id text, add column if not exists etapa text,
                             add column if not exists valor numeric(14,2), add column if not exists probabilidade int, add column if not exists previsao date;
alter table ck_interacoes    add column if not exists cliente_id text, add column if not exists tipo text, add column if not exists data timestamptz;
alter table ck_apresentacoes add column if not exists titulo text;
alter table ck_quadros       add column if not exists titulo text, add column if not exists cliente_id text, add column if not exists viagem_id text;
alter table ck_contatos      add column if not exists cliente_id text, add column if not exists nome text;
alter table ck_swot          add column if not exists escopo text, add column if not exists referencia text;

create table if not exists ck_preferencias (
  dono          uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  favoritos     jsonb not null default '{"clients":[],"groups":[]}'::jsonb,
  ajustes       jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- ─────────────────────── RLS ───────────────────────
-- Base comercial: qualquer usuário LIBERADO (pode_acessar) lê e importa; apagar cliente é de gestor.
-- Workspace: cada um enxerga e grava apenas os próprios registros.
do $$
declare t text;
begin
  foreach t in array array['ck_grupos','ck_clientes','ck_veiculos','ck_vendas','ck_frota','ck_importacoes']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t||'_sel', t);
    execute format('create policy %I on %I for select to authenticated using (pode_acessar())', t||'_sel', t);
    execute format('drop policy if exists %I on %I', t||'_ins', t);
    execute format('create policy %I on %I for insert to authenticated with check (pode_acessar())', t||'_ins', t);
    execute format('drop policy if exists %I on %I', t||'_upd', t);
    execute format('create policy %I on %I for update to authenticated using (pode_acessar()) with check (pode_acessar())', t||'_upd', t);
    execute format('drop policy if exists %I on %I', t||'_del', t);
    execute format('create policy %I on %I for delete to authenticated using (pode_acessar() and (%L in (''ck_vendas'',''ck_frota'') or eh_gestor()))', t||'_del', t, t);
  end loop;
  foreach t in array array['ck_eventos','ck_notas','ck_viagens','ck_oportunidades','ck_interacoes',
                           'ck_apresentacoes','ck_quadros','ck_contatos','ck_swot','ck_preferencias']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t||'_dono', t);
    execute format('create policy %I on %I for all to authenticated using (pode_acessar() and dono = auth.uid()) with check (pode_acessar() and dono = auth.uid())', t||'_dono', t);
  end loop;
end $$;

grant select, insert, update, delete on
  ck_grupos, ck_clientes, ck_veiculos, ck_vendas, ck_frota, ck_importacoes,
  ck_eventos, ck_notas, ck_viagens, ck_oportunidades, ck_interacoes, ck_apresentacoes, ck_quadros, ck_contatos, ck_swot, ck_preferencias
  to authenticated;

-- ─────────────────────── REGRA ÚNICA DE FATURAMENTO ───────────────────────
-- Faturam: FECHADA, LIBERADA, BLOQUEADA, IMPRESSA (e IMPRESSO, grafia do extrato).
-- Não faturam: GRAVADA, DELETADA. Devolução entra negativa.
create or replace function ck_fatura(etapa text) returns boolean
language sql immutable as $$ select upper(coalesce(etapa,'')) in ('FECHADA','LIBERADA','BLOQUEADA','IMPRESSA','IMPRESSO') $$;
grant execute on function ck_fatura(text) to authenticated;

-- ─────────────────────── VISÕES (Tableau / SQL) ───────────────────────
-- recriadas do zero a cada execução (dependentes primeiro)
drop view if exists ck_vw_cliente_mes;
drop view if exists ck_vw_orcamentos;
drop view if exists ck_vw_vendas;
create view ck_vw_vendas with (security_invoker = on) as
select v.data, date_trunc('month', v.data)::date as mes, v.pedido, v.etapa, ck_fatura(v.etapa) as fatura, v.tipo,
       v.valor, case when v.tipo = 'DEVOLUCAO' then -v.valor else v.valor end as valor_assinado,
       case when ck_fatura(v.etapa) then (case when v.tipo = 'DEVOLUCAO' then -v.valor else v.valor end) else 0 end as faturamento_real,
       v.qtd, v.produto_codigo, v.produto_descricao, v.grupo_produto, ve.marca as veiculo_marca, ve.modelo as veiculo_modelo,
       c.codigo as cliente_codigo, c.documento as cliente_cnpj, c.razao_social, c.nome_fantasia, c.cidade, c.uf, c.graduacao,
       g.id as grupo_codigo, g.nome as grupo_economico, v.loja, v.loja_uf, v.vendedor
from ck_vendas v
join ck_clientes c on c.id = v.cliente_id
left join ck_grupos g on g.id = c.grupo_id
left join ck_veiculos ve on ve.id = v.veiculo_id;

-- Orçamentos do Sistema de Orçamentação ligados pelo CNPJ (só dígitos)
create view ck_vw_orcamentos with (security_invoker = on) as
select o.id, o.numero, o.versao, o.data, o.status, o.total, o.veiculo, o.ident_tipo, o.ident_valor, o.tipo_servico,
       regexp_replace(coalesce(c.cnpj,''), '\D', '', 'g') as cnpj,
       coalesce(c.nome_fantasia, c.razao_social) as cliente, u.codigo as unidade,
       (o.data + o.validade_dias) >= current_date as vigente,
       ck.id as ck_cliente_id
from orcamentos o
left join clientes  c  on c.id = o.cliente_id
left join unidades  u  on u.id = o.unidade_id
left join ck_clientes ck on ck.documento = regexp_replace(coalesce(c.cnpj,''), '\D', '', 'g') and ck.documento <> '';

-- Faturamento x orçamentos por cliente e mês (cruzamento dos dois sistemas)
create view ck_vw_cliente_mes with (security_invoker = on) as
with f as (
  select cliente_codigo, mes, sum(faturamento_real) as faturamento_real, count(distinct pedido) filter (where tipo = 'VENDA' and fatura) as vendas
  from ck_vw_vendas group by 1, 2
), o as (
  select ck.codigo as cliente_codigo, date_trunc('month', vo.data)::date as mes, count(*) as orcamentos, sum(vo.total) as valor_orcado,
         sum(vo.total) filter (where vo.status = 'Aprovado') as valor_aprovado
  from ck_vw_orcamentos vo join ck_clientes ck on ck.id = vo.ck_cliente_id group by 1, 2
)
select coalesce(f.cliente_codigo, o.cliente_codigo) as cliente_codigo, coalesce(f.mes, o.mes) as mes,
       coalesce(f.faturamento_real, 0) as faturamento_real, coalesce(f.vendas, 0) as vendas,
       coalesce(o.orcamentos, 0) as orcamentos, coalesce(o.valor_orcado, 0) as valor_orcado, coalesce(o.valor_aprovado, 0) as valor_aprovado
from f full join o on o.cliente_codigo = f.cliente_codigo and o.mes = f.mes;

grant select on ck_vw_vendas, ck_vw_orcamentos, ck_vw_cliente_mes to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- PRONTO. Próximos passos (detalhados no README):
-- 1. Authentication → URL Configuration → Redirect URLs: adicione o endereço do Cockpit.
-- 2. Publique o Cockpit (index.html + config.js + ícones) e entre com o mesmo acesso do Orçamento.
-- 3. No Cockpit, Base de dados: importe a base de clientes e depois o extrato de vendas.
-- ═══════════════════════════════════════════════════════════════════════
