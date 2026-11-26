# 0006. Catálogo multifonte: asset em partes, classificação à parte e sugestão determinística

**Status:** proposta em 26/11/2026, aguardando as decisões DB1 a DB5 do Fred. Detalhes em [`docs/specs/banco-multifonte.md`](../specs/banco-multifonte.md). Complementa o [ADR 0001](0001-acervo-estatico-e-copia-ao-salvar.md) e segue o [ADR 0005](0005-limitacoes-reversiveis.md).

## Contexto

O acervo do MVP tem 1.687 questões do ENEM num só arquivo (`assets/acervo/acervo-v1.json`), e nenhuma foi classificada: só as de Matemática, Inglês e Espanhol têm matéria, porque a fonte garante. O Direciona propõe etapas por matéria, mas não consegue apontar para questões do acervo. A próxima fase acrescenta fontes (dados e PDFs oficiais do INEP) e precisa que o Direciona use o acervo, sem servidor, no plano Spark, com repositório público e sem gabarito.

## Decisão

1. **Asset v2 em partes.** O `assets/acervo/v2/index.json` tem fontes, taxonomia, lista das partes e contagens por matéria e dificuldade. Há uma parte por área (`{área}.json`). O `BankCatalog` ganha `summary()`, que lê só o índice, e carrega as partes sob demanda. O leitor v1 continua aceitando o formato antigo.
2. **Classificação fora do texto e fora do adaptador.** Matéria e assunto vêm de `tool/acervo/classification/<fonte>.jsonl`, em git, com quem classificou (`source`, `rule`, `agent`, `model` ou `human`), validados contra uma lista fechada (`tool/acervo/taxonomy.json`). A correção humana sempre prevalece. O build falha se alguma questão ficar sem matéria.
3. **Uma fonte legal, vários adaptadores.** `sources.json` ganha `kind` (`questions` ou `metadata`) e `adapters`. Uma fonte de metadados, como os microdados do INEP, enriquece questões existentes sem trazer texto.
4. **Ids publicados são permanentes.** Um teste compara com a lista de ids já publicados. Remover exige uma entrada em `removed.json`, com motivo, que também serve de registro do canal de remoção.
5. **A IA não escolhe questões.** Ela continua recebendo só números agregados (agora também `bankAvailable`), e a lista sugerida sai de uma função pura e determinística no domínio (`suggestBankQuestions`), com a dificuldade injetável (`difficultyOf`).
6. **Interruptor único** `appConfig/runtime.directionBankEnabled`, com padrão `true`, que devolve o Direciona ao comportamento do MVP.

## Alternativas descartadas

- **Manter um arquivo só:** mais simples hoje, mas o Direciona teria de carregar o texto inteiro só para contar questões por matéria, e o arquivo cresce com cada fonte.
- **Uma parte por fonte:** isola o cache por fonte, mas o Direciona e a busca filtram por área e matéria, não por fonte, então carregaria tudo do mesmo jeito.
- **Classificação dentro do adaptador ou gravada no cache da fonte:** mistura o que a fonte diz com o que inferimos, e impede a correção humana versionada.
- **A IA escolher os ids da lista:** abre espaço para id inventado, exige mandar ids ou texto no pedido (fere a CA-D6) e não é reproduzível.
- **Dificuldade pela avaliação da comunidade:** com agregação na leitura (ADR 0003), escolher entre centenas de candidatas custaria centenas de leituras e exigiria rede. Fica para quando houver contadores (Blaze).
- **Catálogo no Firestore ou baixado do Hosting:** os motivos do ADR 0001 continuam: cota, busca por texto e demo offline.

## Consequências

- O Direciona planeja com o índice (poucos KB) e carrega só a área de cada etapa com sugestão. A tela do Acervo continua carregando tudo, como hoje.
- Os limites de tamanho viram constantes testadas (3 MiB por parte e 12 MiB no total). Passou disso, o próximo passo é baixar do Hosting, com outra decisão.
- Toda questão nova passa pelo mesmo processo de classificação e revisão por amostra, o que custa tempo de uma pessoa a cada lote grande.
- Os catálogos falsos dos testes precisam implementar `summary()`, e os testes que liam o v1 passam a ler o v2.
- O `acervo-v1.json` sai do `pubspec.yaml`. Apagar o arquivo exige o OK do Fred.

## Como desfazer

- **Voltar ao Direciona do MVP:** `directionBankEnabled=false` no console, sem nova versão.
- **Voltar a um arquivo só:** gerar o asset no formato v1. O leitor v1 continua no app, e só o `AssetBankCatalog` muda.
- **Trocar a origem da dificuldade:** passar outro `difficultyOf` (por exemplo, contadores de avaliações). O asset e as telas não mudam.
- **Corrigir uma classificação:** uma linha com `by: human` no `.jsonl` e um novo build.
