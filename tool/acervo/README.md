# Script do acervo

Gera o asset do acervo de questões (só leitura), por padrão no formato v2 em `assets/acervo/v2/` (`index.json` mais uma parte por área; o `acervo-v1.json` antigo fica no repositório, fora do `pubspec.yaml`), a partir das fontes autorizadas em `sources.json`. Só biblioteca padrão do Python 3.12; não há `requirements.txt`. Só este script acessa a rede: o app nunca acessa a API.

## Gerar

Na raiz do repositório:

```bash
python -I tool/acervo/build_acervo.py
```

- Leva cerca de 1,5 min na primeira vez (cerca de 150 pedidos, a 1 por segundo) e menos de 1 s a partir do cache.
- O cache fica em `build/acervo-cache/` (fora do git) e guarda a data de geração; a mesma entrada gera o mesmo arquivo, byte a byte. Para refazer do zero, apague a pasta.
- O relatório (contagem por edição, por área e exclusões por motivo) é impresso e gravado em `build/acervo-report.md`.
- Opções: `--offline` (só cache), `--generated-at AAAA-MM-DD`, `--cache-dir`, `--out-dir`, `--report`, `--sources`, `--font`, `--format v1` (arquivo único antigo, em `--out`), `--allow-unclassified` (só até a classificação ficar pronta).

## Classificação e formato v2

- `taxonomy.json`: lista fechada de matérias (por área) e assuntos (por matéria), com `taxonomyVersion`. Única fonte da verdade; o índice do asset leva a lista.
- `classification/enem.jsonl`: matéria e assunto de cada questão (gerado por `classify.py merge`). Sem ele, o build falha ("sem matéria"), a menos que se use `--allow-unclassified`. Precedência: `human` > `source` > `rule` > `agent`/`model`. Veja `classification/README.md`.
- `classify.py batches | merge | sample`: lotes para os classificadores, validação e junção das respostas, amostra para conferência.
- `ids-v1.txt` e `removed.json`: os 1.687 ids já publicados nunca somem sem uma entrada em `removed.json` (motivo e data).
- Limites: 3 MiB por parte e 12 MiB no total; o build falha se passar.
- `sources.json` aceita `kind` (`questions` ou `metadata`) e `adapters`; ausentes, valem `questions` e `[id]`.

## Testes

```bash
python -I -m unittest discover -s tool/acervo/tests
```

## O que o script faz

- Recusa fonte sem `authorized: true`, sem link ou sem evidência da situação da licença em `sources.json` (a aplicação da licença às provas não está confirmada; o campo é só registro interno).
- Descarta as respostas na leitura: `correctAlternative` e `isCorrect` são removidos antes de gravar no cache.
- Exclui (e conta por motivo): imagem no contexto, em `files` ou em alternativa; número de alternativas diferente de 5; alternativa vazia; fórmula em LaTeX; caractere sem glifo na Inter; língua inconsistente na API.
- Limpa a marcação (negrito, itálico com `*` e `_`, links, listas, HTML e escapes), normaliza para NFC e arruma os espaços, mantendo os créditos.
- Não classifica o assunto (tarefa A2). `subject` só sai preenchido onde a fonte garante (Matemática, Inglês, Espanhol).

## Acrescentar uma fonte

1. Criar `sources/<fonte>.py` com um `SourceAdapter` (veja `sources/base.py`).
2. Registrar em `sources/__init__.py`.
3. Acrescentar a entrada em `sources.json`, com licença (registro interno, sem afirmar que vale para as provas), atribuição, aviso, link oficial, evidência e `authorized: true` (só com autorização por escrito de quem tem os direitos).

O script principal não muda.

## Particularidades da API do ENEM

- O `offset` segue o número da questão, não a posição, então a paginação perde as questões de língua estrangeira repetidas. O adaptador deduplica as repetições da fronteira e busca as que faltam uma a uma, conferindo contra o resumo da edição.
- Limite de 50 por página e 1 pedido por segundo; 429 vem com `Retry-After`.
- Em alguns anos a API devolve outra língua ao pedir espanhol ou inglês; essas questões são excluídas.
