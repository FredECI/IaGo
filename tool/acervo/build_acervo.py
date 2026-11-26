"""Gera assets/acervo/acervo-v1.json a partir das fontes autorizadas.

Uso (na raiz do repositório):
    python -I tool/acervo/build_acervo.py

Só este script acessa a rede; o app nunca acessa a API. Veja o README.md.
"""

import argparse
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # necessário com `python -I`; só código nosso mora aqui

from fetcher import Fetcher  # noqa: E402
from glyphs import covered_codepoints, missing_chars  # noqa: E402
from sources import ADAPTERS  # noqa: E402

SCHEMA_VERSION = 1
REQUIRED_SOURCE_FIELDS = (
    "id", "name", "via", "officialUrl", "license", "licenseUrl",
    "licenseEvidence", "attribution", "notice",
)
ASSET_SOURCE_FIELDS = (
    "id", "name", "via", "officialUrl", "attribution", "notice",
)
REPO = os.path.dirname(os.path.dirname(HERE))
AREA_LABEL = {
    "languages": "Linguagens", "humanities": "Humanas",
    "naturalSciences": "Natureza", "mathematics": "Matemática",
}
FORBIDDEN_KEYS = ("correctAlternative", "isCorrect", "gabarito")

_LATEX = re.compile(
    r"\\[a-zA-Z]+|\\\(|\$\$|\^\{|(?<![A-Za-z\d])\$(?=\S)[^$\n]*?(?<=\S)\$"
)


class SourceRefused(Exception):
    pass


def load_sources(path):
    """Lê o registro e recusa fonte sem ``authorized: true`` ou sem link/evidência."""
    with open(path, encoding="utf-8") as f:
        sources = json.load(f)["sources"]
    seen = set()
    for s in sources:
        sid = s.get("id", "?")
        if s.get("authorized") is not True:
            raise SourceRefused(f"fonte '{sid}' recusada: falta authorized: true em sources.json")
        missing = [k for k in REQUIRED_SOURCE_FIELDS if not str(s.get(k, "")).strip()]
        if missing:
            raise SourceRefused(f"fonte '{sid}' recusada: faltam campos {missing}")
        if not (s["officialUrl"].startswith("https://") and s["licenseUrl"].startswith("https://")):
            raise SourceRefused(f"fonte '{sid}' recusada: officialUrl e licenseUrl devem ser https")
        if sid in seen:
            raise SourceRefused(f"id de fonte repetido: {sid}")
        if sid not in ADAPTERS:
            raise SourceRefused(f"fonte '{sid}' sem adaptador em tool/acervo/sources/")
        seen.add(sid)
    return sources


def exclusion_reasons(q, covered):
    """Motivos de exclusão: os do adaptador (imagem) e os comuns a todas as fontes."""
    reasons = list(q.exclusions)
    if len(q.alternatives) != 5:
        reasons.append("alternativas_diferente_de_5")
    elif any(not a.strip() for a in q.alternatives):
        reasons.append("alternativa_vazia")
    if not q.statement.strip():
        reasons.append("enunciado_vazio")
    text = q.statement + "\n" + "\n".join(q.alternatives)
    if _LATEX.search(text):
        reasons.append("formula_latex")
    if covered is not None and missing_chars(text, covered):
        reasons.append("glifo_ausente_na_inter")
    return reasons


def question_to_dict(q):
    d = {
        "id": q.id,
        "source": q.source,
        "year": q.edition,
        "number": q.number,
        "area": q.area,
    }
    if q.subject:
        d["subject"] = q.subject
    d["statement"] = q.statement
    d["alternatives"] = q.alternatives
    return d


def build(sources, fetcher_factory, covered, generated_at, log=print):
    kept, excluded = [], []  # excluded: (RawQuestion, reasons)
    used_sources = []
    for s in sources:
        adapter = ADAPTERS[s["id"]](covered=covered)
        fetcher = fetcher_factory(adapter)
        used_sources.append({k: s[k] for k in ASSET_SOURCE_FIELDS})
        for q in adapter.iter_questions(fetcher.get_json, log):
            reasons = exclusion_reasons(q, covered)
            (excluded if reasons else kept).append((q, reasons) if reasons else q)
    ids = [q.id for q in kept] + [e[0].id for e in excluded]
    if len(ids) != len(set(ids)):
        dup = sorted({i for i in ids if ids.count(i) > 1})
        raise ValueError(f"ids repetidos: {dup[:5]}")
    kept.sort(key=lambda q: (q.source, q.edition, q.number, q.id))
    asset = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": generated_at,
        "sources": used_sources,
        "questions": [question_to_dict(q) for q in kept],
    }
    return asset, kept, excluded


def dump_asset(asset):
    """JSON estável: uma questão por linha (diffs legíveis), UTF-8, sem espaços à toa."""

    def j(v):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"))

    head = [
        f'"schemaVersion":{asset["schemaVersion"]}',
        f'"generatedAt":{j(asset["generatedAt"])}',
        f'"sources":{j(asset["sources"])}',
    ]
    qs = ",\n".join(j(q) for q in asset["questions"])
    return "{" + ",".join(head) + ',"questions":[\n' + qs + "\n]}\n"


def forbidden_keys(node):
    """Chaves de resposta em qualquer nível do asset ."""
    found = set()
    if isinstance(node, dict):
        for k, v in node.items():
            if k.lower() in {x.lower() for x in FORBIDDEN_KEYS}:
                found.add(k)
            found |= forbidden_keys(v)
    elif isinstance(node, list):
        for v in node:
            found |= forbidden_keys(v)
    return found


def has_forbidden_word(text):
    """A palavra 'gabarito' não pode aparecer no asset, fora de URLs (o link oficial do
    INEP termina em 'provas-e-gabaritos')."""
    return "gabarito" in re.sub(r"https?://\S+", "", text, flags=re.IGNORECASE).lower()


def _count(items):
    counts = {}
    for r in items:
        counts[r] = counts.get(r, 0) + 1
    return sorted(counts.items(), key=lambda x: (-x[1], x[0]))


def report_text(kept, excluded):
    areas = list(AREA_LABEL)
    total = len(kept) + len(excluded)
    lines = ["# Relatório do acervo", ""]
    lines.append(f"Lidas: {total} | Aproveitadas: {len(kept)} | Excluídas: {len(excluded)}")
    editions = sorted({q.edition for q in kept} | {e[0].edition for e in excluded})
    lines += ["", "## Por edição (aproveitadas / lidas)", ""]
    for y in editions:
        k = sum(q.edition == y for q in kept)
        t = k + sum(e[0].edition == y for e in excluded)
        lines.append(f"- {y}: {k} / {t}")
    lines += ["", "## Por área (aproveitadas / lidas)", ""]
    for a in areas:
        k = sum(q.area == a for q in kept)
        t = k + sum(e[0].area == a for e in excluded)
        lines.append(f"- {AREA_LABEL[a]}: {k} / {t}")
    lines += ["", "## Edição x área (aproveitadas)", ""]
    lines.append("| Edição | " + " | ".join(AREA_LABEL[a] for a in areas) + " |")
    lines.append("| --- |" + " --- |" * len(areas))
    for y in editions:
        cells = [str(sum(q.edition == y and q.area == a for q in kept)) for a in areas]
        lines.append(f"| {y} | " + " | ".join(cells) + " |")
    lines += ["", "## Exclusões por motivo (primeiro motivo de cada questão; somam o total)", ""]
    lines += [f"- {r}: {n}" for r, n in _count(e[1][0] for e in excluded)]
    lines += ["", "## Exclusões por motivo (todos os motivos; uma questão pode ter mais de um)", ""]
    lines += [f"- {r}: {n}" for r, n in _count(r for e in excluded for r in e[1])]
    lines += ["", "## Exclusões por área", ""]
    for a in areas:
        lines.append(f"- {AREA_LABEL[a]}: {sum(e[0].area == a for e in excluded)}")
    return "\n".join(lines) + "\n"


def generated_at_for(cache_dir, override):
    """Data fixada no 1º uso do cache, para a mesma entrada gerar o mesmo arquivo."""
    if override:
        datetime.date.fromisoformat(override)
        return override
    marker = os.path.join(cache_dir, "generated-at.txt")
    if os.path.exists(marker):
        with open(marker, encoding="utf-8") as f:
            return f.read().strip()
    value = datetime.date.today().isoformat()
    os.makedirs(cache_dir, exist_ok=True)
    with open(marker, "w", encoding="utf-8") as f:
        f.write(value)
    return value


def main(argv=None):
    p = argparse.ArgumentParser(description="Gera o asset do acervo de questões.")
    p.add_argument("--sources", default=os.path.join(HERE, "sources.json"))
    p.add_argument("--cache-dir", default=os.path.join(REPO, "build", "acervo-cache"))
    p.add_argument("--out", default=os.path.join(REPO, "assets", "acervo", "acervo-v1.json"))
    p.add_argument("--report", default=os.path.join(REPO, "build", "acervo-report.md"))
    p.add_argument("--font", default=os.path.join(REPO, "assets", "fonts", "Inter-Regular.ttf"))
    p.add_argument("--generated-at", default=None, help="AAAA-MM-DD (padrão: fixada no cache)")
    p.add_argument("--offline", action="store_true", help="só usa o cache; falha se faltar")
    args = p.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    try:
        sources = load_sources(args.sources)
    except SourceRefused as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 2
    covered = covered_codepoints(args.font)
    gen = generated_at_for(args.cache_dir, args.generated_at)
    fetchers = []

    def factory(adapter):
        f = Fetcher(
            args.cache_dir, [adapter.allowed_prefix], adapter.sanitize, offline=args.offline
        )
        fetchers.append(f)
        return f

    asset, kept, excluded = build(sources, factory, covered, gen, log=lambda m: print(m, flush=True))
    out = dump_asset(asset)
    if has_forbidden_word(out):
        print("ERRO: a palavra 'gabarito' aparece no asset", file=sys.stderr)
        return 3
    bad = forbidden_keys(asset)  # cinto e suspensório; o teste também confere
    if bad:
        print(f"ERRO: campo de resposta no asset: {sorted(bad)}", file=sys.stderr)
        return 3
    report = report_text(kept, excluded)
    for path, text in ((args.out, out), (args.report, report)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print(report)
    print(
        f"Pedidos de rede: {sum(f.network_requests for f in fetchers)}; "
        f"acertos de cache: {sum(f.cache_hits for f in fetchers)}"
    )
    print(f"Asset: {args.out} ({len(out.encode('utf-8'))} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
