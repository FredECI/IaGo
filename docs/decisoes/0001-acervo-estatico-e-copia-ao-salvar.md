# 0001. Acervo em arquivo estático, com cópia ao salvar

**Status:** aceita em 07/11/2026 (D3 e D4 aprovadas pelo Fred), com a condição de que a limitação seja fácil de desfazer. Detalhes em [`docs/specs/mvp-27-11.md`](../specs/mvp-27-11.md).

## Contexto

O MVP ganha um acervo de questões compartilhado, começando pelo ENEM, com cerca de 1.700 questões só de texto. A busca atual roda no cliente, sobre as questões do usuário, e o plano Spark oferece 50 mil leituras por dia. Listas e PDF só conhecem questões do próprio usuário. O modo demo precisa funcionar sem rede.

## Decisão

1. **O acervo é um asset do app** (`assets/acervo/acervo-v1.json`), gerado por um script local que roda antes do build, com um adaptador por fonte e um registro de fontes com licença e atribuição. Ele não fica no Firestore, e o app não consulta a API externa em tempo de execução.
2. **A busca continua no cliente**, com `QuestionFilter` e `QuestionFacets`, usando um estado de filtro separado do de "Minhas questões". As telas leem o acervo só pela interface assíncrona e paginável `BankCatalog`; hoje, a implementação filtra em memória.
3. **Usar uma questão significa copiá-la** para `users/{uid}/questions`, com id `bank_{bankId}` e `origin=bank`. Listas e PDF não mudam.
4. **O gabarito é descartado no script.**

## Alternativas descartadas

- **Acervo no Firestore:** seriam 1.700 leituras por carga completa, ou cerca de 68 mil por dia no piloto, acima da cota. Também não há busca por texto no modo Standard.
- **Consulta ao vivo à API:** quebra a demo offline, tem limite de 1 pedido por segundo e depende de um projeto comunitário.
- **Baixar do Hosting:** exige `http` e cache próprio, sem vantagem no tamanho atual (cerca de 0,7 MiB com gzip).
- **Lista com referências:** exige listas mistas e mudanças em `resolveQuestions`, editor e PDF. Editar também teria que virar cópia.

## Consequências

- Zero leitura no Firestore para navegar pelo acervo, e funciona offline em web e Android.
- Atualizar o acervo exige nova versão do app, o que é aceitável para provas anuais.
- Cada questão salva gasta 1 gravação, dentro da cota.
- O texto entra no repositório público e no site, o que torna a questão de direitos autorais uma decisão explícita (D4 na spec). Remover uma questão exige nova versão.
- Uma exceção à diretriz "sem scripts de admin": o script é uma ferramenta de desenvolvimento, como `tool/build_fonts.py`, e não toca dados de produção.
- A métrica H1 precisa separar `origin`, para o acervo não inflar a ativação.
- Migrar para servidor no futuro exigiria um índice de busca próprio (8 a 16 h e custo do serviço).

## Como desfazer

- **Mais fontes:** um adaptador novo em `tool/acervo/sources/` e uma entrada em `sources.json` com `authorized: true` e evidência. Custa de 4 a 8 h por fonte e depende de autorização por escrito de quem tem os direitos. Telas, busca e avaliações não mudam, porque o id é estável e prefixado pela fonte.
- **Acervo fora do asset** (Firestore, API própria ou consulta ao vivo): só uma nova implementação do `BankCatalog`. Avaliações, listas e cópias não migram. Consulta ao vivo exige um proxy no servidor (plano Blaze), de 6 a 10 h.
- **Questões com imagem:** o campo `media` já está reservado no formato do asset. Falta guardar as imagens e mostrá-las, de 8 a 14 h, além de resolver os direitos sobre imagens de terceiros.
- **Gabarito:** decisão de produto (D3). O asset passa para `schemaVersion` 2, com o campo novo, de 4 a 6 h.
- **Referência em vez de cópia:** continua cara (listas mistas, editor e PDF). Não há motivo previsto para isso.
