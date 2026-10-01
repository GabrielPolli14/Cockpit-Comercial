# Cockpit Comercial — produção (projeto Supabase próprio)

O Cockpit usa um projeto Supabase **só dele**, separado do Sistema de Orçamentação.
Login, liberação de acessos e dados ficam isolados. O modelo de acesso é o mesmo do Orçamento:
a conta nasce pendente e o administrador libera.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `index.html` | O sistema inteiro (inclui o gerador de PowerPoint e o cliente do Supabase). |
| `config.js` | URL e chave do **projeto do Cockpit**. Fica na mesma pasta do `index.html`. |
| `favicon.ico`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `manifest.webmanifest` | Ícones do Cockpit. |
| `cockpit_schema.sql` | Cria usuários, perfis, tabelas `ck_`, regras de acesso (RLS) e visões. Roda uma vez. |

---

## Passo 1 — Criar o projeto

1. Em [supabase.com](https://supabase.com), clique em **New project**.
2. Nome: `cockpit-comercial`. Região: **South America (São Paulo)**. Guarde a senha do banco.
3. Aguarde o projeto ficar pronto (1 a 2 minutos).

## Passo 2 — Rodar o SQL

1. Menu lateral → **SQL Editor** → **New query**.
2. Abra o `cockpit_schema.sql`, copie todo o conteúdo, cole e clique em **Run**. Deve aparecer *Success*.
3. Confira em **Table Editor**: `usuarios`, `dominios_permitidos` e as tabelas `ck_` (`ck_clientes`, `ck_vendas`, `ck_grupos`, `ck_eventos`, `ck_notas`, …).
4. Pode rodar de novo quando quiser: o script não apaga nem duplica nada.

## Passo 3 — Configurar o login

**Authentication → Sign In / Providers → Email:**
- **Enable sign ups:** ligado (cada pessoa cria o próprio acesso pela tela do Cockpit).
- **Confirm email:** desligado.
- Recomendado: **Prevent use of leaked passwords** ligado.

**Authentication → URL Configuration:**
- **Site URL:** o endereço do Cockpit, por exemplo `https://SEU-USUARIO.github.io/cockpit-comercial/`.
- **Redirect URLs:** adicione o mesmo endereço. É por ele que o link de “Esqueci minha senha” volta para o Cockpit.

## Passo 4 — Preencher o config.js

**Project Settings → API** do projeto **novo**:
- **Project URL** → cole em `url`.
- **anon / publishable key** → cole em `key`.

```js
window.COCKPIT_CONFIG = {
  url: 'https://xxxxxxxx.supabase.co',
  key: 'sb_publishable_...'
};
```

**Nunca** use a chave `service_role` aqui.

## Passo 5 — Publicar (GitHub Pages)

1. No GitHub, crie o repositório **`cockpit-comercial`** (separado do Orçamento).
2. Clique em **Add file → Upload files** e arraste `index.html`, `config.js` e os 6 arquivos de ícone e manifest. Depois, **Commit changes**.
3. Em **Settings → Pages**, escolha **Deploy from a branch → main → / (root)** e clique em **Save**.
4. Em 1 a 2 minutos o endereço aparece: `https://SEU-USUARIO.github.io/cockpit-comercial/`. Confira se é o mesmo que você colocou no Passo 3.

## Passo 6 — Primeiro acesso

1. Abra o Cockpit e clique em **Criar conta**. **O primeiro cadastro do projeto vira administrador já liberado**: faça o seu antes de todo mundo.
2. Os cadastros seguintes nascem **pendentes**. O Hub avisa quando há alguém aguardando.
3. Para liberar, vá em **Configurações → Acessos** e use **Liberar acesso**, **Bloquear** ou a troca de perfil.
4. Em **Domínios aceitos no cadastro**, adicione `autoglass.com.br` para que só e-mails da empresa consigam criar conta.

Perfis:
- **Analista:** usa o sistema.
- **Gestor:** também vê a lista de acessos e pode apagar cadastros.
- **Administrador:** libera acessos e troca perfis.

## Passo 7 — Carregar a carteira

Em **Base de dados**:
1. Importe primeiro a **base de clientes** (`Clientes_Locadoras.csv`).
2. Depois importe o **extrato de vendas** (`Frotas_2026.csv`).
3. Para atualizar, importe o extrato novo. As vendas do mesmo intervalo de datas são substituídas, sem duplicar.

## Regras

- **Faturamento real:** vendas faturáveis (Fechada, Liberada, Bloqueada, Impressa) menos devoluções. Gravada e Deletada aparecem nos filtros, mas não faturam.
- **Privacidade:** a base comercial (clientes e vendas) é compartilhada pelos usuários liberados. Agenda, notas, viagens, quadros, oportunidades, SWOT, apresentações e favoritos são **pessoais**.
- **Tableau/SQL:** `ck_vw_vendas` traz linha a linha com `faturamento_real`.
- **Sessão própria:** a sessão é `cockpit-auth`. Mesmo publicado no mesmo GitHub Pages do Orçamento, um sistema não interfere no login do outro.

## Desenvolvimento

```
npm i -D esbuild pptxgenjs @supabase/supabase-js
node tools/build-standalone.mjs   # gera dist/cockpit-standalone.html → publique como index.html
```
