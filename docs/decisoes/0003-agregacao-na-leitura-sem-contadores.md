# 0003. Agregação na leitura, sem contadores

**Status:** aceita em 07/11/2026, junto com a aprovação de D1 a D5, com a condição de que a limitação seja fácil de desfazer. Detalhes em [`docs/specs/mvp-27-11.md`](../specs/mvp-27-11.md).

## Contexto

Avaliações e reputação precisam de dados agregados entre usuários, sem servidor. A solução usual, com contadores mantidos pelo cliente, abre espaço para fraude e inconsistência, e exige regras complexas com `getAfter`.

## Decisão

1. **Cada ato é um documento com id determinístico:** `questionRatings/{bankId}_{uid}` e `helpfulVotes/{replyId}_{voterUid}`. O id garante um por pessoa, e as regras conferem autor, faixa de valores e coerência.
2. **Nenhum contador é gravado.** Médias e totais vêm de `count()` e `average()` na leitura, a 1 leitura por lote de até 1.000 entradas de índice.
3. **O resumo aparece no detalhe, sob demanda**, com pelo menos 3 avaliações e sempre comparado à média da matéria. A reputação aparece ao lado da média do grupo.

## Alternativas descartadas

- **Contadores validados por regra:** funcionam, mas cada escrita exige várias checagens em lote, e excluir uma conta precisaria recalcular tudo.
- **Trigger em Cloud Function:** é a solução robusta, mas exige Blaze.
- **Ler todas as avaliações e somar no cliente:** gasta uma leitura por avaliação e expõe mais dados.

## Consequências

- Nada a forjar nem a reconciliar. Excluir a conta é só apagar os próprios documentos.
- **Sem filtro nem ordenação por dificuldade no MVP**, porque isso exigiria o valor agregado de todas as questões de uma vez.
- Agregação não funciona offline nem em tempo real: a tela mostra "indisponível sem conexão".
- Fraude com várias contas não é resolvida. O convite e o e-mail verificado reduzem o risco, mas só um servidor daria proteção real.
- O documento individual tem `uid` e pode ser lido por contas. A interface nunca mostra isso, e os termos informam.
- Migrar para contadores depois custaria de 6 a 10 h, com uma execução única sobre o histórico.

## Como desfazer

O caminho para contadores agregados não migra nenhum documento:

1. As avaliações continuam como estão: `questionRatings/{bankId}_{uid}` é a fonte da verdade. O `bankId` é o id estável do catálogo e não depende de onde o acervo mora.
2. Uma Cloud Function (plano Blaze) mantém uma coleção derivada, por exemplo `questionRatingStats/{bankId}`, com contagem e somas de dificuldade e qualidade, a cada criação, alteração ou exclusão.
3. Uma execução única lê as avaliações existentes e preenche a coleção derivada.
4. `RatingRepository.summary` passa a ler o contador e volta à agregação na leitura se ele faltar. As telas não mudam.
5. Com o valor agregado por questão, filtro e ordenação por dificuldade viram uma consulta comum.

Custa de 6 a 10 h, mais a execução única, e depende de dinheiro (Blaze). A proteção contra várias contas só melhora com servidor, por exemplo com limite por dia na própria função.
