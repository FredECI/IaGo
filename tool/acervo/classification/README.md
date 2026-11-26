# Classificação do acervo (matéria e assunto)

Cada questão do acervo precisa de uma **matéria** (lista fechada por área) e, quando couber, de um **assunto** (lista fechada por matéria). As listas estão em [`../taxonomy.json`](../taxonomy.json): `areas` dá as matérias de cada área e `subjects` dá os assuntos de cada matéria. **Use só os nomes de lá, escritos exatamente assim.**

## Quem faz o quê

- `batches/lote-1.jsonl` a `lote-8.jsonl`: as 1.687 questões, em 8 lotes de ~211. **Entrada** (gerada por `classify.py batches`, não edite).
- `out/lote-N.jsonl`: a **saída** de cada classificador, uma por lote. O classificador do lote N grava só o `out/lote-N.jsonl`.
- `enem.jsonl`: resultado do `merge` (é o que o `build_acervo.py` lê). Não edite à mão; correção humana é uma linha nova com `"by":"human"` em outro `.jsonl` desta pasta.

## Entrada: uma questão por linha em `batches/lote-N.jsonl`

```json
{"id":"enem-2021-26","area":"languages","subject":"Inglês","statement":"início do enunciado [...] fim do enunciado","alternatives":["A…","B…","C…","D…","E…"]}
```

| Campo | Significado |
| --- | --- |
| `id` | Id do acervo. Devolva igual |
| `area` | `languages`, `humanities`, `naturalSciences` ou `mathematics` |
| `subject` | Só aparece quando a fonte já garante a matéria (Matemática, Inglês e Espanhol). Nesses casos, **repita a matéria** e classifique só o assunto |
| `statement` | Enunciado truncado em cerca de 350 caracteres: começo e fim, com `[...]` no meio |
| `alternatives` | As 5 alternativas, cada uma truncada em cerca de 40 caracteres |

## Saída: uma linha por questão em `out/lote-N.jsonl`

```json
{"id":"enem-2021-26","subject":"Português","topic":"Coesão e coerência","confidence":"high"}
```

| Campo | Regra |
| --- | --- |
| `id` | Obrigatório. Exatamente o `id` da entrada. Todas as questões do lote devem ter uma linha |
| `subject` | Obrigatório. Uma matéria de `areas[area]` em `taxonomy.json` (Linguagens: Português, Literatura, Redação, Inglês, Espanhol, Artes, Educação Física; Humanas: História, Geografia, Filosofia, Sociologia; Natureza: Biologia, Física, Química; Matemática: Matemática). Nunca de outra área |
| `topic` | Um assunto de `subjects[subject]` em `taxonomy.json`, ou `""` se nenhum servir. **Não invente assunto e não use "Outros"** |
| `confidence` | `"high"`, `"medium"` ou `"low"`. Use `low` quando o texto truncado não bastar para decidir |

Formato do arquivo: JSON Lines em UTF-8, **uma linha por questão, sem linha em branco, sem comentário e sem texto fora do JSON**. Não grave gabarito, resposta, justificativa nem outros campos (o `merge` ignora o que não conhece).

Dicas de classificação:

- Decida pelo que a questão pede, não pelo tema do texto-base. Texto de jornal com pergunta sobre coesão é Português; um poema com pergunta sobre o movimento literário é Literatura.
- Questões de linguagens sem língua estrangeira entram em Português, Literatura, Artes ou Educação Física. Redação não tem questão objetiva: não use.
- Em Ciências da Natureza, as questões interdisciplinares vão para a matéria que resolve o problema (a que daria a ferramenta principal).
- Em Matemática, escolha o assunto pelo conteúdo usado na resolução (Geometria plana ou espacial, Funções, Estatística, etc.). A dica de habilidade da matriz (`skillHints` em `taxonomy.json`) só vale se o campo `skill` existir, o que ainda não acontece.

## Juntar tudo (`merge`)

Na raiz do repositório, depois que os 8 arquivos de `out/` existirem:

```bash
python -I tool/acervo/classify.py merge
```

O comando valida cada linha contra os lotes e a taxonomia e grava `tool/acervo/classification/enem.jsonl`, com `by: "agent"` e `reviewed: false`.

- Matéria fora da área: a linha é **descartada** e conta como problema.
- Id desconhecido ou sem resposta: problema. O comando termina com código 1 (use `--allow-partial` para gravar mesmo assim).
- Assunto fora da taxonomia: vira `""`, com aviso. Matéria diferente da que a fonte garante: a da fonte prevalece, com aviso.
- Confiança inválida vira `low`, com aviso.

Corrija as linhas citadas em `out/lote-N.jsonl` e rode de novo (é idempotente).

## Regerar o asset e conferir

```bash
python -I tool/acervo/build_acervo.py --offline            # usa o cache; falha se faltar matéria
python -I tool/acervo/classify.py sample --n 100 --seed 2026   # amostra opcional em build/acervo-classify/amostra.csv
flutter test test/data/bank_v2_test.dart
```

No resultado, as questões ficam com `classifiedBy: "agent"` e o app mostra "Classificação automática".
