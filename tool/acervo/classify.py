"""Classificação do acervo em matéria e assunto (lista fechada em taxonomy.json).

Uso (na raiz do repositório):
    python -I tool/acervo/classify.py batches [--files 4]
    python -I tool/acervo/classify.py merge
    python -I tool/acervo/classify.py sample [--n 100 --seed 2026]

Fluxo: ``batches`` lê o asset v2 e grava os lotes em ``classification/batches/``;
cada classificador grava ``classification/out/lote-N.jsonl``; ``merge`` valida
tudo e junta em ``classification/enem.jsonl``, que o ``build_acervo.py`` lê.
Só biblioteca padrão. Veja classification/README.md.
"""

import argparse
import csv
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import acervo_v2 as v2  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
CLASSIFICATION = os.path.join(HERE, "classification")


def trim_statement(text, limit):
    """Corta o enunciado em ~``limit`` caracteres, guardando o começo e o fim
    (a pergunta costuma vir no fim, depois do texto-base)."""
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    tail = max(limit // 3, 1)
    head = limit - tail
    return text[:head].rstrip() + " [...] " + text[-tail:].lstrip()


def trim_alternative(text, limit):
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def read_shards(shards_dir):
    """Questões do asset v2, na ordem das áreas e das partes."""
    questions = []
    for a in v2.AREA_ORDER:
        path = os.path.join(shards_dir, f"{a}.json")
        with open(path, encoding="utf-8") as f:
            questions += json.load(f)["questions"]
    return questions


def batch_line(q, statement_chars, alt_chars):
    line = {"id": q["id"], "area": q["area"]}
    if q.get("subject"):
        line["subject"] = q["subject"]
    line["statement"] = trim_statement(q["statement"], statement_chars)
    line["alternatives"] = [trim_alternative(a, alt_chars) for a in q["alternatives"]]
    return line


def split_even(items, parts):
    """Corta a lista (já ordenada) em ``parts`` pedaços contíguos de tamanho parecido."""
    n = len(items)
    size, extra = divmod(n, parts)
    out, start = [], 0
    for i in range(parts):
        end = start + size + (1 if i < extra else 0)
        out.append(items[start:end])
        start = end
    return out


def cmd_batches(args):
    questions = read_shards(args.shards_dir)
    lines = [batch_line(q, args.statement_chars, args.alt_chars) for q in questions]
    os.makedirs(args.out, exist_ok=True)
    for name in os.listdir(args.out):
        if name.startswith("lote-") and name.endswith(".jsonl"):
            os.remove(os.path.join(args.out, name))
    for n, chunk in enumerate(split_even(lines, args.files), 1):
        path = os.path.join(args.out, f"lote-{n}.jsonl")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            for line in chunk:
                f.write(v2.jdump(line) + "\n")
        areas = sorted({x["area"] for x in chunk})
        print(f"{path}: {len(chunk)} questões, {os.path.getsize(path)} bytes, áreas {areas}")
    return 0


def read_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if line.strip():
                try:
                    rows.append((n, json.loads(line)))
                except ValueError as e:
                    rows.append((n, {"_error": f"JSON inválido ({e})"}))
    return rows


def merge(batch_rows, answer_rows, taxonomy):
    """Valida as respostas contra os lotes e a taxonomia.

    ``batch_rows``: linhas dos lotes (id, area, subject opcional).
    ``answer_rows``: lista de (origem, linha) das respostas.
    Devolve (entradas, problemas, avisos). Problema = resposta descartada ou
    questão sem resposta; aviso = ajuste feito sem perder a resposta.
    """
    base = {r["id"]: r for r in batch_rows}
    chosen, problems, warnings = {}, [], []
    for origin, row in answer_rows:
        if "_error" in row:
            problems.append(f"{origin}: {row['_error']}")
            continue
        qid = row.get("id")
        if qid not in base:
            problems.append(f"{origin}: id desconhecido: {qid}")
            continue
        area = base[qid]["area"]
        subject = row.get("subject")
        if subject not in taxonomy["areas"][area]:
            problems.append(f"{origin}: {qid}: matéria '{subject}' fora do catálogo de {area}")
            continue
        fixed = base[qid].get("subject")
        if fixed and subject != fixed:
            warnings.append(f"{origin}: {qid}: matéria '{subject}' trocada por '{fixed}' (a fonte garante)")
            subject = fixed
        topic = row.get("topic") or ""
        if topic and topic not in taxonomy["subjects"][subject]:
            warnings.append(f"{origin}: {qid}: assunto '{topic}' fora da taxonomia de {subject}; ficou vazio")
            topic = ""
        confidence = row.get("confidence")
        if confidence not in v2.CONFIDENCES:
            warnings.append(f"{origin}: {qid}: confiança '{confidence}' inválida; ficou 'low'")
            confidence = "low"
        if qid in chosen:
            warnings.append(f"{origin}: {qid}: resposta repetida; vale a última")
        chosen[qid] = {
            "id": qid, "subject": subject, "topic": topic, "by": "agent",
            "confidence": confidence, "reviewed": False,
        }
    entries = [chosen[r["id"]] for r in batch_rows if r["id"] in chosen]
    for r in batch_rows:
        if r["id"] not in chosen:
            problems.append(f"sem resposta: {r['id']}")
    return entries, problems, warnings


def cmd_merge(args):
    taxonomy = v2.load_taxonomy(args.taxonomy)
    batch_rows = []
    for name in sorted(os.listdir(args.batches)):
        if name.startswith("lote-") and name.endswith(".jsonl"):
            batch_rows += [r for _, r in read_jsonl(os.path.join(args.batches, name))]
    if not batch_rows:
        print(f"ERRO: nenhum lote em {args.batches}", file=sys.stderr)
        return 2
    answer_rows = []
    if os.path.isdir(args.answers):
        for name in sorted(os.listdir(args.answers)):
            if name.startswith("lote-") and name.endswith(".jsonl"):
                answer_rows += [(f"{name}:{n}", r)
                                for n, r in read_jsonl(os.path.join(args.answers, name))]
    entries, problems, warnings = merge(batch_rows, answer_rows, taxonomy)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8", newline="\n") as f:
        for e in entries:
            f.write(v2.jdump(e) + "\n")
    with_topic = sum(bool(e["topic"]) for e in entries)
    low = sum(e["confidence"] == "low" for e in entries)
    print(f"{len(entries)} de {len(batch_rows)} questões em {args.output}")
    print(f"com assunto: {with_topic}; confiança baixa: {low}")
    for w in warnings[:50]:
        print(f"aviso: {w}")
    if len(warnings) > 50:
        print(f"... e mais {len(warnings) - 50} avisos")
    for p in problems[:50]:
        print(f"PROBLEMA: {p}", file=sys.stderr)
    if len(problems) > 50:
        print(f"... e mais {len(problems) - 50} problemas", file=sys.stderr)
    return 1 if problems and not args.allow_partial else 0


def pick_sample(entries, n, seed):
    """Amostra estratificada: cotas iguais por área; dentro da área, até 40% das
    vagas vão para confiança baixa ou média (as mais duvidosas)."""
    rng = random.Random(seed)
    per_area = {a: n // len(v2.AREA_ORDER) for a in v2.AREA_ORDER}
    for a in v2.AREA_ORDER[: n - sum(per_area.values())]:
        per_area[a] += 1
    chosen = []
    for a in v2.AREA_ORDER:
        pool = sorted((e for e in entries if e["area"] == a), key=lambda e: e["id"])
        doubtful = [e for e in pool if e.get("confidence") in ("low", "medium")]
        quota = min(per_area[a], len(pool))
        take_doubtful = min(len(doubtful), round(quota * 0.4))
        picked = rng.sample(doubtful, take_doubtful)
        rest = [e for e in pool if e not in picked]
        picked += rng.sample(rest, min(quota - len(picked), len(rest)))
        chosen += sorted(picked, key=lambda e: e["id"])
    return chosen


def cmd_sample(args):
    entries = {}
    for _, row in read_jsonl(args.classification):
        entries[row["id"]] = row
    questions = {q["id"]: q for q in read_shards(args.shards_dir)}
    rows = []
    for qid, e in entries.items():
        if qid in questions:
            rows.append({**e, "area": questions[qid]["area"]})
    picked = pick_sample(rows, args.n, args.seed)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "area", "subject", "topic", "by", "confidence", "statement", "ok"])
        for e in picked:
            q = questions[e["id"]]
            w.writerow([e["id"], e["area"], e["subject"], e.get("topic", ""), e["by"],
                        e.get("confidence", ""), trim_statement(q["statement"], 300), ""])
    print(f"{len(picked)} questões em {args.out}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Classificação do acervo.")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("batches", help="grava os lotes de classificação")
    b.add_argument("--shards-dir", default=os.path.join(REPO, "assets", "acervo", "v2"))
    b.add_argument("--out", default=os.path.join(CLASSIFICATION, "batches"))
    b.add_argument("--files", type=int, default=4)
    b.add_argument("--statement-chars", type=int, default=350)
    b.add_argument("--alt-chars", type=int, default=40)

    m = sub.add_parser("merge", help="valida as respostas e junta em enem.jsonl")
    m.add_argument("--taxonomy", default=os.path.join(HERE, "taxonomy.json"))
    m.add_argument("--batches", default=os.path.join(CLASSIFICATION, "batches"))
    m.add_argument("--answers", default=os.path.join(CLASSIFICATION, "out"))
    m.add_argument("--output", default=os.path.join(CLASSIFICATION, "enem.jsonl"))
    m.add_argument("--allow-partial", action="store_true",
                   help="não falha se faltar resposta ou houver resposta inválida")

    s = sub.add_parser("sample", help="amostra estratificada para conferência")
    s.add_argument("--classification", default=os.path.join(CLASSIFICATION, "enem.jsonl"))
    s.add_argument("--shards-dir", default=os.path.join(REPO, "assets", "acervo", "v2"))
    s.add_argument("--out", default=os.path.join(REPO, "build", "acervo-classify", "amostra.csv"))
    s.add_argument("--n", type=int, default=100)
    s.add_argument("--seed", type=int, default=2026)

    args = p.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        return {"batches": cmd_batches, "merge": cmd_merge, "sample": cmd_sample}[args.cmd](args)
    except v2.BuildError as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
