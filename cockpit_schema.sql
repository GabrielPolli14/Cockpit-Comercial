-- ═══════════════════════════════════════════════════════════════════════
-- COCKPIT COMERCIAL · banco no Supabase (projeto PRÓPRIO, separado do Orçamento)
-- Cole este arquivo inteiro no SQL Editor de um projeto novo e execute uma vez.
-- É seguro reexecutar: nada é apagado nem duplicado.
-- ═══════════════════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";

-- ─────────────────────── USUÁRIOS E PERFIS ───────────────────────
-- Mesma lógica do Sistema de Orçamentação: a conta nasce PENDENTE e um administrador libera.
do $$ begin
  create type perfil_usuario as enum ('administrador','gestor','analista');
exception when duplicate_object then null; end $$;

create table if not exists usuarios (
  id         uuid primary key references auth.users(id) on delete cascade,
  nome       text not null default '',
  email      text not null,
  telefone   text,
  whatsapp   text,
  perfil     perfil_usuario not null default 'analista',
  ativo      boolean not null default false,
  created_at timestamptz not null default now()
);

-- todo cadastro no Authentication ganha uma linha aqui; o PRIMEIRO vira administrador já liberado
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean;
begin
  select count(*) = 0 into primeiro from public.usuarios;
  insert into public.usuarios (id, nome, email, telefone, whatsapp, perfil, ativo)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email,'@',1)),
          new.email, new.raw_user_meta_data->>'telefone', new.raw_user_meta_data->>'whatsapp',
          (case when primeiro then 'administrador' else 'analista' end)::perfil_usuario, primeiro)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- usuários que já existiam no Authentication antes do script
insert into usuarios (id, nome, email, ativo)
select u.id, coalesce(nullif(u.raw_user_meta_data->>'nome',''), split_part(u.email,'@',1)), u.email, false
from auth.users u on conflict (id) do nothing;
update usuarios set perfil = 'administrador', ativo = true
 where id = (select id from usuarios order by created_at, email limit 1)
   and not exists (select 1 from usuarios where perfil = 'administrador');

create or replace function perfil_atual() returns perfil_usuario
language sql stable security definer set search_path = public as $$
  select coalesce((select perfil from usuarios where id = auth.uid()), 'analista'::perfil_usuario);
$$;
create or replace function eh_gestor() returns boolean
language sql stable as $$ select perfil_atual() in ('administrador','gestor'); $$;
-- porteiro de todas as tabelas: ativo = false revoga o acesso na hora
create or replace function pode_acessar() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios where id = auth.uid() and ativo);
$$;

-- domínios de e-mail aceitos no autocadastro (vazio = qualquer e-mail, sempre nascendo pendente)
create table if not exists dominios_permitidos (dominio text primary key, criado_em timestamptz not null default now());
create or replace function public.validar_dominio() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from dominios_permitidos)
     and not exists (select 1 from dominios_permitidos d where lower(new.email) like '%@' || lower(d.dominio)) then
    raise exception 'Cadastro não liberado para e-mails @%. Fale com o administrador.', split_part(new.email,'@',2);
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_domain on auth.users;
create trigger on_auth_user_domain before insert on auth.users
  for each row execute function public.validar_dominio();

-- só administrador libera, bloqueia ou troca perfil (ninguém se autopromove)
create or replace function public.protege_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if perfil_atual() <> 'administrador' then
    new.perfil := old.perfil; new.ativo := old.ativo; new.email := old.email;
  end if;
  return new;
end $$;
drop trigger if exists tg_protege_usuario on usuarios;
create trigger tg_protege_usuario before update on usuarios
  for each row execute function public.protege_usuario();

alter table usuarios enable row level security;
alter table dominios_permitidos enable row level security;
drop policy if exists usuarios_sel on usuarios;
create policy usuarios_sel on usuarios for select to authenticated using (id = auth.uid() or eh_gestor());
drop policy if exists usuarios_ins_self on usuarios;
create policy usuarios_ins_self on usuarios for insert to authenticated with check (id = auth.uid() and ativo = false and perfil = 'analista');
drop policy if exists usuarios_upd on usuarios;
create policy usuarios_upd on usuarios for update to authenticated using (id = auth.uid() or eh_gestor()) with check (id = auth.uid() or eh_gestor());
drop policy if exists dominios_sel on dominios_permitidos;
create policy dominios_sel on dominios_permitidos for select to authenticated using (true);
drop policy if exists dominios_adm on dominios_permitidos;
create policy dominios_adm on dominios_permitidos for all to authenticated using (perfil_atual() = 'administrador') with check (perfil_atual() = 'administrador');
grant usage on schema public to authenticated;
grant select, insert, update on usuarios to authenticated;
grant select, insert, delete on dominios_permitidos to authenticated;
grant execute on function perfil_atual(), eh_gestor(), pode_acessar() to authenticated;

-- ─────────────────────── BASE COMERCIAL (compartilhada pela equipe) ───────────────────────
create table if not exists ck_grupos (
  id         text primary key,                 -- código do cliente principal do grupo
  nome       text not null,
  criado_em  timestamptz not null default now()
);

create table if not exists ck_clientes (
  id              text primary key,            -- = código do cliente
  codigo          text not null unique,
  documento       text,                        -- CNPJ/CPF só dígitos
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

grant select on ck_vw_vendas to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- PRONTO. Próximos passos (detalhados no README):
-- 1. Authentication → Providers → Email: "Enable sign ups" ligado, "Confirm email" desligado.
-- 2. Authentication → URL Configuration: Site URL e Redirect URLs = endereço do Cockpit.
-- 3. Abra o Cockpit e use "Criar conta": o PRIMEIRO cadastro vira administrador já liberado.
-- 4. Os demais entram pendentes; libere em Configurações → Acessos, dentro do Cockpit.
-- 5. Base de dados: importe a base de clientes e depois o extrato de vendas.
-- ═══════════════════════════════════════════════════════════════════════
