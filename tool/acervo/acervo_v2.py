"""Formato v2 do acervo: taxonomia, classificação e partes por área.

Usado por ``build_acervo.py`` e ``classify.py``. Só biblioteca padrão. Veja
docs/specs/banco-multifonte.md (seções 1 e 2).
"""

import json
import os

SCHEMA_VERSION = 2
AREA_ORDER = ("languages", "humanities", "naturalSciences", "mathematics")
AREA_LABEL = {
    "languages": "Linguagens", "humanities": "Humanas",
    "naturalSciences": "Natureza", "mathematics": "Matemática",
}
# Precedência no build: human > source > rule > agent ou model.
BY_RANK = {"human": 0, "source": 1, "rule": 2, "agent": 3, "model": 3}
CONFIDENCES = ("high", "medium", "low")
MAX_SHARD_BYTES = 3 * 1024 * 1024  # maxBankShardBytes
MAX_TOTAL_BYTES = 12 * 1024 * 1024  # maxBankTotalBytes
REMOVAL_REASONS = ("duplicata", "pedido_de_remocao", "erro_de_extracao")


class BuildError(Exception):
    """Erro de dados que deve parar o build (mensagem em português)."""


def jdump(v):
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def load_taxonomy(path):
    with open(path, encoding="utf-8") as f:
        t = json.load(f)
    areas, subjects = t.get("areas"), t.get("subjects")
    if not isinstance(areas, dict) or set(areas) != set(AREA_ORDER):
        raise BuildError("taxonomy.json: 'areas' deve ter as 4 áreas")
    if not isinstance(subjects, dict):
        raise BuildError("taxonomy.json: falta 'subjects'")
    listed = [s for a in AREA_ORDER for s in areas[a]]
    if sorted(listed) != sorted(subjects):
        raise BuildError("taxonomy.json: 'subjects' deve ter exatamente as matérias de 'areas'")
    for subject, topics in subjects.items():
        if len(topics) != len(set(topics)):
            raise BuildError(f"taxonomy.json: assunto repetido em {subject}")
        if len(topics) > 14:
            raise BuildError(f"taxonomy.json: {subject} deve ter no máximo 14 assuntos")
    if not isinstance(t.get("taxonomyVersion"), int):
        raise BuildError("taxonomy.json: falta taxonomyVersion")
    return t


def check_subject_topic(taxonomy, area, subject, topic, who):
    """Valida matéria (do catálogo da área) e assunto (da lista da matéria)."""
    if subject not in taxonomy["areas"][area]:
        raise BuildError(f"{who}: matéria '{subject}' fora do catálogo de {area}")
    if topic and topic not in taxonomy["subjects"][subject]:
        raise BuildError(f"{who}: assunto '{topic}' fora da taxonomia de {subject}")


def read_classification(directory):
    """Lê os ``*.jsonl`` da pasta (só o 1º nível). Devolve {id: entrada}.

    Mais de uma entrada para o mesmo id: vale a de maior precedência (``by``);
    empate, a do arquivo que vem depois na ordem alfabética.
    """
    result = {}
    if not os.path.isdir(directory):
        return result
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not (name.endswith(".jsonl") and os.path.isfile(path)):
            continue
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    e = json.loads(line)
                except ValueError as err:
                    raise BuildError(f"{name}:{n}: JSON inválido ({err})")
                if not isinstance(e, dict) or not e.get("id") or not e.get("subject"):
                    raise BuildError(f"{name}:{n}: faltam 'id' e 'subject'")
                if e.get("by", "agent") not in BY_RANK:
                    raise BuildError(f"{name}:{n}: 'by' inválido: {e.get('by')}")
                e.setdefault("by", "agent")
                old = result.get(e["id"])
                if old is None or BY_RANK[e["by"]] <= BY_RANK[old["by"]]:
                    result[e["id"]] = e
    return result


def resolve_question(q, cl, taxonomy, who):
    """(subject, topic, by) de uma questão, pela precedência. ``q`` é RawQuestion."""
    if cl is not None and cl["by"] == "human":
        subject, by = cl["subject"], "human"
    elif q.subject:
        subject, by = q.subject, "source"
    elif cl is not None:
        subject, by = cl["subject"], cl["by"]
    else:
        return None, "", None
    topic = (cl or {}).get("topic") or ""
    check_subject_topic(taxonomy, q.area, subject, topic, who)
    return subject, topic, by


def check_classification_ids(classification, known_ids):
    unknown = sorted(set(classification) - set(known_ids))
    if unknown:
        raise BuildError(
            f"{len(unknown)} id(s) da classificação não existem no acervo "
            f"(deriva?): {unknown[:5]}"
        )


def v2_question(q, subject, topic, by):
    d = {"id": q.id, "source": q.source, "year": q.edition}
    variant = getattr(q, "variant", None)
    if variant:
        d["variant"] = variant
    d["number"] = q.number
    d["area"] = q.area
    if subject:
        d["subject"] = subject
        if topic:
            d["topic"] = topic
        d["classifiedBy"] = by
    d["statement"] = q.statement
    d["alternatives"] = q.alternatives
    return d


def load_removed(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        items = json.load(f).get("removed", [])
    out = {}
    for r in items:
        if r.get("reason") not in REMOVAL_REASONS or not r.get("date") or not r.get("id"):
            raise BuildError(f"removed.json: entrada inválida: {r}")
        out[r["id"]] = r
    return out


def load_ids_v1(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [ln.strip() for ln in f if ln.strip()]


def check_published_ids(ids_v1, removed, current_ids):
    missing = sorted(i for i in ids_v1 if i not in current_ids and i not in removed)
    if missing:
        raise BuildError(
            f"{len(missing)} id(s) publicado(s) sumiram do acervo sem entrada em "
            f"removed.json: {missing[:5]}"
        )


def group_by_area(questions):
    """Agrupa os dicts v2 por área. Devolve {área: [dict]} com as 4 áreas."""
    by_area = {a: [] for a in AREA_ORDER}
    for d in questions:
        by_area[d["area"]].append(d)
    return by_area


def dump_shard(area, questions):
    """Uma questão por linha (diffs legíveis), UTF-8, sem espaços à toa."""
    head = f'{{"schemaVersion":{SCHEMA_VERSION},"area":{jdump(area)},"questions":[\n'
    return head + ",\n".join(jdump(q) for q in questions) + "\n]}\n"


def build_counts(questions):
    """Uma linha por (área, matéria, dificuldade); só questões com matéria."""
    tally = {}
    for d in questions:
        if "subject" not in d:
            continue
        key = (d["area"], d["subject"], d.get("difficulty"))
        tally[key] = tally.get(key, 0) + 1
    rows = []
    for (area, subject, diff), n in sorted(
        tally.items(),
        key=lambda kv: (AREA_ORDER.index(kv[0][0]), kv[0][1], kv[0][2] or 0),
    ):
        row = {"area": area, "subject": subject}
        if diff is not None:
            row["difficulty"] = diff
        row["count"] = n
        rows.append(row)
    return rows


def build_index(generated_at, sources, taxonomy, shard_counts, counts, shard_dir):
    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": generated_at,
        "taxonomyVersion": taxonomy["taxonomyVersion"],
        "sources": sources,
        "taxonomy": taxonomy["subjects"],
        "shards": [
            {"area": a, "path": f"{shard_dir}/{a}.json", "count": shard_counts[a]}
            for a in AREA_ORDER
        ],
        "counts": counts,
    }


def dump_index(index):
    """Índice pequeno e legível: uma linha por fonte, parte e contagem."""

    def block(key, items):
        return f'"{key}":[\n' + ",\n".join(jdump(i) for i in items) + "\n]"

    head = [
        f'"schemaVersion":{index["schemaVersion"]}',
        f'"generatedAt":{jdump(index["generatedAt"])}',
        f'"taxonomyVersion":{index["taxonomyVersion"]}',
    ]
    tax = ",\n".join(f"{jdump(k)}:{jdump(v)}" for k, v in index["taxonomy"].items())
    return (
        "{" + ",".join(head) + ",\n"
        + block("sources", index["sources"]) + ",\n"
        + '"taxonomy":{\n' + tax + "\n},\n"
        + block("shards", index["shards"]) + ",\n"
        + block("counts", index["counts"]) + "\n}\n"
    )


def check_sizes(files):
    """``files``: {nome: texto}. Aplica os limites com nome (CA-R7)."""
    total = 0
    for name, text in files.items():
        size = len(text.encode("utf-8"))
        total += size
        if name != "index.json" and size > MAX_SHARD_BYTES:
            raise BuildError(f"parte {name} com {size} bytes passa de maxBankShardBytes")
    if total > MAX_TOTAL_BYTES:
        raise BuildError(f"acervo com {total} bytes passa de maxBankTotalBytes")


def coverage_text(questions):
    """Seção do relatório: cobertura por área e classificação por ``by``."""
    lines = ["", "## Classificação (v2)", ""]
    total = len(questions)
    lines.append(f"- Com matéria: {sum('subject' in d for d in questions)} / {total}")
    lines.append(f"- Com assunto: {sum('topic' in d for d in questions)} / {total}")
    lines += ["", "| Área | Total | Com matéria | Com assunto |", "| --- | --- | --- | --- |"]
    for a in AREA_ORDER:
        qs = [d for d in questions if d["area"] == a]
        lines.append(
            f"| {AREA_LABEL[a]} | {len(qs)} | {sum('subject' in d for d in qs)} "
            f"| {sum('topic' in d for d in qs)} |"
        )
    lines += ["", "Por quem classificou:", ""]
    tally = {}
    for d in questions:
        by = d.get("classifiedBy", "sem matéria")
        tally[by] = tally.get(by, 0) + 1
    lines += [f"- {k}: {n}" for k, n in sorted(tally.items())]
    return "\n".join(lines) + "\n"
