# Cockpit Comercial — produção

Workspace comercial interligado ao **Sistema de Orçamentação Autoglass**: mesmo banco no Supabase,
mesmo login, mesma liberação de acessos e orçamentos ligados aos clientes pelo CNPJ.

## Arquivos da publicação

| Arquivo | Para que serve |
|---|---|
| `index.html` | O sistema inteiro (inclui o gerador de PowerPoint e o cliente do Supabase). |
| `config.js` | O mesmo do Orçamento. Opcional se o Cockpit ficar numa subpasta do repositório do Orçamento. |
| `favicon.ico`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `manifest.webmanifest` | Ícone do Cockpit no navegador e na tela de início. |
| `cockpit_schema.sql` | Cria as tabelas do Cockpit (prefixo `ck_`) no mesmo projeto do Orçamento. Roda uma vez. |

---

## Passo 1 — Banco (Supabase)

1. Abra o projeto do Orçamento no Supabase (`sldajxdoclkojauyadir`).
2. Menu lateral → **SQL Editor** → **New query**.
3. Abra o arquivo `cockpit_schema.sql`, copie todo o conteúdo, cole e clique em **Run**. Deve terminar com *Success. No rows returned*.
   - Se aparecer *“Rode primeiro o supabase_schema.sql do Sistema de Orçamentação”*, você está em outro projeto. Confira o nome no topo da tela.
   - O script pode ser executado de novo sem problema: não apaga dados nem duplica nada.
4. Confira em **Table Editor**: devem aparecer as tabelas `ck_clientes`, `ck_vendas`, `ck_grupos`, `ck_frota`, `ck_veiculos`, `ck_eventos`, `ck_notas`, `ck_viagens`, `ck_oportunidades`, `ck_quadros`, `ck_swot`, `ck_apresentacoes`, `ck_interacoes`, `ck_contatos`, `ck_preferencias`, `ck_importacoes`. As tabelas do Orçamento continuam iguais.

## Passo 2 — Publicar (GitHub Pages)

**Recomendado: subpasta no repositório do Orçamento.** Assim o Cockpit usa o mesmo `config.js` e o
mesmo login, sem configurar nada.

1. No repositório do Orçamento: **Add file → Upload files**.
2. Arraste a pasta `cockpit` inteira (com `index.html` e os ícones). O `config.js` pode ficar só na raiz, onde já está.
3. **Commit changes**. Em 1–2 minutos o endereço fica disponível:
   `https://SEU-USUARIO.github.io/orcamentos-autoglass/cockpit/`

*Alternativa:* um repositório separado (`cockpit-comercial`), com `index.html`, `config.js` e os ícones
na raiz. Depois, em **Settings → Pages**, escolha **Deploy from a branch → main → / (root)**.

## Passo 3 — Endereço autorizado no Supabase

**Authentication → URL Configuration → Redirect URLs → Add URL**: cole o endereço do Cockpit,
por exemplo `https://SEU-USUARIO.github.io/orcamentos-autoglass/cockpit/`, e salve.
Isso é necessário para o link de “Esqueci minha senha” voltar para o Cockpit.

## Passo 4 — Primeiro acesso

1. Abra o Cockpit e entre com **o mesmo e-mail e senha do Orçamento**.
2. Usuários novos podem usar **Criar conta**. A conta nasce **pendente** e é liberada pelo administrador em **Orçamentos → Configurações → Acessos**. A liberação vale para os dois sistemas.
3. Bloquear alguém no Orçamento bloqueia o acesso ao Cockpit na hora.
4. No mesmo GitHub Pages, quem entra em um sistema já está logado no outro (mesma sessão).

## Passo 5 — Carregar a carteira

No Cockpit, **Base de dados**:

1. Importe **primeiro a base de clientes** (`Clientes_Locadoras.csv`). Os grupos econômicos são montados pelo *Cód. Cliente Principal*.
2. Depois importe o **extrato de vendas** (`Frotas_2026.csv`).
3. Para atualizar, importe o extrato novo. As vendas do mesmo intervalo de datas são **substituídas**: cancelamentos e mudanças de etapa ficam corretos e nada duplica.

## Regras e interligação

- **Faturamento real:** vendas faturáveis (Fechada, Liberada, Bloqueada, Impressa) menos devoluções. Gravada e Deletada aparecem nos filtros, mas não faturam. É a mesma regra no Dashboard, nas Apresentações, no Agente e na visão `ck_vw_vendas`.
- **Orçamentos:** aparecem no perfil do cliente (aba *Orçamentos*), no Dashboard (no mesmo recorte) e no Hub, ligados pelo CNPJ. Para os atalhos “Novo orçamento”, ajuste `orcamentoUrl` no `config.js`.
- **Privacidade:** a base comercial é compartilhada pela equipe liberada. Agenda, notas, viagens, quadros, oportunidades, SWOT, apresentações e favoritos são **pessoais**: cada usuário vê só os seus.
- **Para Tableau/SQL:**
  - `ck_vw_vendas`: linha a linha, com `faturamento_real`.
  - `ck_vw_orcamentos`: orçamentos já ligados ao cliente do Cockpit.
  - `ck_vw_cliente_mes`: faturamento × orçamentos por cliente e mês.

## Desenvolvimento

```
npm i -D esbuild pptxgenjs @supabase/supabase-js
node tools/build-standalone.mjs   # gera dist/cockpit-standalone.html → publique como index.html
```
