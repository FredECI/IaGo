# Script do acervo

Gera `assets/acervo/acervo-v1.json` (acervo de questões, só leitura) a partir das fontes autorizadas em `sources.json`. Só biblioteca padrão do Python 3.12; não há `requirements.txt`. Só este script acessa a rede: o app nunca acessa a API.

## Gerar

Na raiz do repositório:

```bash
python -I tool/acervo/build_acervo.py
```

- Leva cerca de 1,5 min na primeira vez (cerca de 150 pedidos, a 1 por segundo) e menos de 1 s a partir do cache.
- O cache fica em `build/acervo-cache/` (fora do git) e guarda a data de geração; a mesma entrada gera o mesmo arquivo, byte a byte. Para refazer do zero, apague a pasta.
- O relatório (contagem por edição, por área e exclusões por motivo) é impresso e gravado em `build/acervo-report.md`.
- Opções: `--offline` (só cache), `--generated-at AAAA-MM-DD`, `--cache-dir`, `--out`, `--report`, `--sources`, `--font`.

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
