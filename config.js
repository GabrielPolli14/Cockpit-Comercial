/* ═══════════════════════════════════════════════════════════════
   COCKPIT COMERCIAL · credenciais do Supabase

   É o MESMO config.js do Sistema de Orçamentação (mesmo projeto, mesmo login).
   Se o Cockpit ficar numa subpasta do repositório do Orçamento (recomendado),
   você nem precisa deste arquivo: o Cockpit lê o config.js da pasta de cima.

   orcamentoUrl (opcional): endereço do Sistema de Orçamentos, para os atalhos
   "Novo orçamento" e "Abrir Orçamentos" dentro do Cockpit.

   A chave publishable é pública por natureza; quem protege os dados é o RLS.
   NUNCA coloque aqui a chave "service_role" nem a senha do banco.
   ═══════════════════════════════════════════════════════════════ */

window.AG_CONFIG = {
  url: 'https://sldajxdoclkojauyadir.supabase.co',
  key: 'sb_publishable_BVVDIK1pGE6q6OLhZJX6FQ_afODSygX',
  orcamentoUrl: '../'   // ajuste para o endereço do Orçamento, ex.: 'https://SEU-USUARIO.github.io/orcamentos-autoglass/'
};
