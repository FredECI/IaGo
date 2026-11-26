"""Extrai as questões objetivas dos cadernos de prova do ENEM (PDF oficial do INEP).

Uso (na raiz do repositório; só aqui se usa `pymupdf`, que NÃO é dependência do app nem do
`build_acervo.py`: instale só na máquina de desenvolvimento, `pip install pymupdf`):

    python -I tool/acervo/extract_inep.py download            # baixa os cadernos (só "PV", nunca gabarito)
    python -I tool/acervo/extract_inep.py extract             # gera tool/acervo/extracted/<edição>.json

O download usa só o link oficial do INEP, uma vez por arquivo, e **recusa** qualquer arquivo
que não seja caderno de questões ("PV"): o gabarito (`GB`) nunca é baixado nem lido.
A leitura do PDF só olha texto, linhas e figuras; uma questão com imagem, gráfico, tabela ou
traço que possa ser fração ou esquema é marcada `hasFigure` e fica fora do acervo.

Formato de saída (contrato de extração do app: enunciado, alternativas, figura, completude):
`{"number", "area", "language", "statement", "alternatives", "hasFigure", "isComplete"}`.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import unicodedata
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CACHE = os.path.join(REPO, "build", "acervo-cache", "inep")
EXTRACTED = os.path.join(HERE, "extracted")
BASE_URL = "https://download.inep.gov.br/enem/provas_e_gabaritos/"

# Cadernos de referência: caderno 1 (azul) no dia 1 e caderno 5 (azul ou amarelo) no dia 2.
# edição -> (ano, variante, [arquivos])
EDITIONS = {
    "2024": (2024, None, ["2024_PV_impresso_D1_CD1.pdf", "2024_PV_impresso_D2_CD5.pdf"]),
    "2025": (2025, None, ["2025_PV_impresso_D1_CD1.pdf", "2025_PV_impresso_D2_CD5.pdf"]),
    "2026": (2026, None, ["2026_PV_impresso_D1_CD1.pdf", "2026_PV_impresso_D2_CD5.pdf"]),
    "2024-ppl": (2024, "ppl", [
        "2024_PV_reaplicacao_PPL_D1_CD1.pdf", "2024_PV_reaplicacao_PPL_D2_CD5.pdf"]),
    "2025-reap-pa": (2025, "reaplicacao", [
        "2025_PV_impresso_D3_CD1.pdf", "2025_PV_impresso_D4_CD5.pdf"]),
    "2025-ppl": (2025, "ppl", [
        "2025_PV_impresso_D5_CD1.pdf", "2025_PV_impresso_D6_CD5.pdf"]),
}

AREA_RANGES = (
    (1, 45, "languages"), (46, 90, "humanities"),
    (91, 135, "naturalSciences"), (136, 180, "mathematics"),
)

PARA, LINE = "\n\n", "\n"
BODY_TOP, BODY_BOTTOM = 62.0, 746.0  # fora disso: cabeçalho, marca d'água e rodapé

_SUB = dict(zip("0123456789+-=()aehijklmnoprstuvx", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ"))
_SUP = dict(zip(
    "0123456789+-=()abcdefghijklmnoprstuvwxyz",
    "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ"))
_WATERMARK = re.compile(r"\d{0,4}ENE[MN]\d{0,4}|\d{1,4}(?=ENE)|\*\w+\*")
_CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
_PRIVATE = re.compile(r"[\ue000-\uf8ff]")
_ZERO_WIDTH = re.compile("[​‌‍⁠﻿­]")
_HEADER = re.compile(r"^quest[ãa]o(\d{1,3})$", re.IGNORECASE)  # sobre o texto sem espaços (2026 espaça as letras)
_LABEL = re.compile(r"^([A-E])[\t ]*$")
# Os marcadores são testados no texto sem espaços: a edição de 2026 espaça as letras.
_SPACES = re.compile(r"\s+")
_SECTION = re.compile(r"^quest[õo]esde\d+a\d+", re.IGNORECASE)
_LANG = re.compile(r"op[çc][ãa]o(ingl[êe]s|espanhol)", re.IGNORECASE)
_PREAMBLE = re.compile(r"^textoparaasquest", re.IGNORECASE)
_STOP = re.compile(r"^(propostadereda|rascunho)", re.IGNORECASE)
_AREA_TITLE = re.compile(r"ESUASTECNOLOGIAS$")


def area_of(number):
    for lo, hi, area in AREA_RANGES:
        if lo <= number <= hi:
            return area
    return None


def clean_text(text):
    """NFC, NBSP e espaços de largura zero, espaços repetidos. Não mexe nas palavras."""
    text = unicodedata.normalize("NFC", text)
    text = text.replace(" ", " ").replace(" ", " ")
    text = _ZERO_WIDTH.sub("", text)
    text = _CONTROL.sub("", text)  # marcadores de lista do PDF (caractere de controle) e afins
    return re.sub(r"[ \t]+", " ", text).strip()


# ---------------------------------------------------------------------------
# Camada do PDF (pymupdf): devolve páginas já filtradas, em itens simples.
# ---------------------------------------------------------------------------

def _line_text(spans):
    """Texto da linha, com índices (subscrito e sobrescrito) em Unicode quando possível.

    Devolve (texto, tamanho_principal, base, problemas). Um índice que não tem caractere
    Unicode correspondente vira um problema, e a questão sai do acervo.
    """
    spans = [s for s in spans if s["text"] != ""]
    if not spans:
        return "", 0.0, 0.0, []
    main = max(spans, key=lambda s: len(s["text"].strip()) * s["size"])
    size, base = main["size"], main["origin"][1]
    parts, problems = [], []
    for s in spans:
        t = s["text"]
        if s["size"] < size * 0.8 and t.strip():
            table = _SUB if s["origin"][1] > base + 0.5 else _SUP
            inner = t.strip()
            mapped = "".join(table.get(c, "") for c in inner)
            if len(mapped) == len(inner):
                t = mapped
            else:
                problems.append("indice_nao_representavel")
        parts.append(t)
    return "".join(parts), size, base, problems


def _guess_split(items, width):
    """Sem divisor desenhado (2024), duas colunas = texto só de cada lado do meio."""
    mid = width / 2
    texts = [i for i in items if i["k"] == "t"]
    left = [t for t in texts if t["x1"] <= mid + 12]
    right = [t for t in texts if t["x0"] >= mid - 12]
    crossing = [t for t in texts if t["x0"] < mid - 12 and t["x1"] > mid + 12]
    if len(left) >= 5 and len(right) >= 5 and not crossing:
        return mid
    return None


def pages_from_pdf(path):
    """Lê o PDF e devolve uma lista de páginas: {"cols": [x_divisão ou None], "items": [...]}.

    Cada item é uma linha de texto (`k="t"`) ou uma marca gráfica (`k="f"`, figura ou traço).
    """
    import pymupdf  # só aqui; ferramenta de extração, fora do app

    pages = []
    with pymupdf.open(path) as doc:
        for page in doc:
            width = page.rect.width
            drawings = page.get_drawings()
            split = None
            for d in drawings:
                r = d["rect"]
                if r.width < 1 and r.height > 400 and BODY_TOP < r.y0 < 120:
                    split = r.x0
            items = []
            for block in page.get_text("dict")["blocks"]:
                x0, y0, x1, y1 = block["bbox"]
                if block["type"] == 1:
                    if y1 < BODY_TOP or y0 > BODY_BOTTOM:
                        continue
                    items.append({"k": "f", "x0": x0, "y0": y0, "x1": x1, "y1": y1,
                                  "thin": min(x1 - x0, y1 - y0) <= 4})
                    continue
                for line in block["lines"]:
                    lx0, ly0, lx1, ly1 = line["bbox"]
                    if ly0 < BODY_TOP or ly0 > BODY_BOTTOM:
                        continue
                    text, size, base, problems = _line_text(line["spans"])
                    if not text.strip() or _WATERMARK.sub("", text).strip() == "":
                        continue
                    first = line["spans"][0]["text"]
                    items.append({
                        "k": "t", "x0": lx0, "y0": ly0, "x1": lx1, "y1": ly1, "text": text,
                        "size": size, "base": base, "first": first,
                        "nspans": len(line["spans"]), "problems": problems,
                        "label_font": "Bundesbahn" in line["spans"][0]["font"],
                    })
            for d in drawings:
                r = d["rect"]
                if r.y1 < BODY_TOP or r.y0 > BODY_BOTTOM or r.x0 >= width - 10 or r.x1 < 0:
                    continue
                if r.width < 1 and r.height > 400:
                    continue  # divisor das colunas
                if r.width > width * 0.95 and r.height > page.rect.height * 0.9:
                    continue  # fundo da página
                if r.width <= 10 and r.height <= 10 and (r.x0 < 24 or r.x0 > 538):
                    continue  # marcas de canto da página
                if r.x0 < 0 or r.x1 < 16 or r.y0 < BODY_TOP - 2 or r.x1 > width + 1:
                    continue  # marcas de canto e do cabeçalho
                items.append({"k": "f", "x0": r.x0, "y0": r.y0, "x1": r.x1, "y1": r.y1,
                              "thin": min(r.width, r.height) <= 4})
            if split is None:
                split = _guess_split(items, width)
            pages.append({"split": split, "items": items})
    return pages


# ---------------------------------------------------------------------------
# Análise (pura, testável sem PDF)
# ---------------------------------------------------------------------------

def _drop_margin_numbers(texts):
    """Remove os números de linha da margem (1, 2, 3...) de poemas e textos longos."""
    cand = [t for t in texts if re.fullmatch(r"\d{1,3}", t["text"].strip())]
    drop = set()
    i = 0
    while i < len(cand):
        j = i + 1
        step = None
        while j < len(cand):
            diff = int(cand[j]["text"]) - int(cand[j - 1]["text"])
            if diff not in (1, 5, 10) or (step is not None and diff != step):
                break
            step = diff
            j += 1
        if j - i >= 3:
            drop.update(id(c) for c in cand[i:j])
        i = max(j, i + 1)
    return [t for t in texts if id(t) not in drop]


def stream(pages):
    """Itens na ordem de leitura (página, coluna esquerda e direita, de cima para baixo).

    Cada texto recebe `page`, `col`, `left` e `right` (margens da coluna na página).
    """
    out = []
    for pn, page in enumerate(pages):
        split = page["split"]
        cols = {0: [], 1: []}
        for it in page["items"]:
            col = 0 if split is None else (0 if (it["x0"] + it["x1"]) / 2 < split else 1)
            cols[col].append(it)
        for col in (0, 1):
            items = sorted(cols[col], key=lambda i: (round(i["y0"], 1), i["x0"]))
            texts = [i for i in items if i["k"] == "t"]
            if not texts:
                for i in items:
                    i.update(page=pn, col=col, left=0, right=0)
                out.extend(items)
                continue
            kept = _drop_margin_numbers(texts)
            left = min(t["x0"] for t in kept)
            right = max(t["x1"] for t in kept)
            keep_ids = {id(t) for t in kept}
            for i in items:
                if i["k"] == "t" and id(i) not in keep_ids:
                    continue
                i.update(page=pn, col=col, left=left, right=right)
                out.append(i)
    return out


def _join_lines(lines):
    """Junta as linhas de um bloco de texto em parágrafos (`\\n\\n`) e versos (`\\n`)."""
    out = ""
    prev = None
    for ln in lines:
        text = clean_text(ln["text"])
        if not text:
            continue
        if prev is None:
            out = text
        else:
            same_block = prev["page"] == ln["page"] and prev["col"] == ln["col"]
            size_change = abs(prev["size"] - ln["size"]) >= 1.2
            if same_block:
                pitch = ln["base"] - prev["base"]
                indent = ln["x0"] >= prev["x0"] + 8
                short_prev = prev["x1"] < prev["right"] - 12
                if ln["size"] < 9.5 and prev["size"] < 9.5:
                    sep = " "  # crédito da fonte, que quebra em várias linhas
                elif size_change or pitch > 1.75 * ln["size"] or indent:
                    sep = PARA
                elif short_prev:
                    sep = LINE
                else:
                    sep = " "
            else:  # continua na outra coluna ou página
                sep = PARA if (size_change or ln["x0"] >= ln["left"] + 8) else " "
            if out.endswith("-") and text.startswith("-") and sep == " ":
                text, sep = text[1:], ""  # hífen repetido na quebra de linha
            out += sep + text
        prev = ln
    return out


def _join_alt(lines):
    """Alternativa: as linhas seguintes são continuação (recuo não é parágrafo)."""
    out = ""
    for ln in lines:
        text = clean_text(ln["text"])
        if text:
            out = f"{out} {text}" if out else text
    return out


class _Q:
    def __init__(self, number, lang, header):
        self.number, self.lang, self.header = number, lang, header
        self.stmt, self.alts, self.preamble = [], [], []
        self.fig = False
        self.figs = []
        self.problems = []
        self.last_alt_line = None


def parse(pages):
    """Devolve (questões, avisos). `questões` no contrato de extração, em ordem do caderno."""
    questions, warnings = [], []
    lang = None
    q = None
    in_alts = False
    mode = "between"  # between | ignore | question
    preamble = []  # linhas do "Texto para as questões X a Y"
    preamble_fig = False
    preamble_for = None  # (lo, hi) ou None
    orphans = 0

    def finish():
        nonlocal q, in_alts
        if q is None:
            return
        alts = [_join_alt(a) for a in q.alts]
        stmt = _join_lines(q.preamble + q.stmt)
        if _PRIVATE.search(stmt + "".join(alts)):
            q.problems.append("glifo_privado")  # símbolo do PDF sem Unicode (seta, etc.)
        complete = (
            len(alts) == 5 and all(alts) and bool(stmt) and not q.problems
        )
        questions.append({
            "number": q.number, "area": area_of(q.number), "language": q.lang,
            "statement": stmt, "alternatives": alts, "hasFigure": q.fig,
            "isComplete": complete, "_figs": q.figs, **({"problems": q.problems} if q.problems else {}),
        })
        q, in_alts = None, False

    for it in stream(pages):
        if it["k"] == "f":
            if q is not None:
                hdr = q.header
                same_header_rule = (
                    it["page"] == hdr["page"] and it["col"] == hdr["col"]
                    and hdr["y0"] - 1 <= it["y0"] <= hdr["y1"] + 1
                    and it["y1"] - it["y0"] <= 8 and it["x0"] >= hdr["x1"] - 2
                )
                if same_header_rule:
                    continue
                if in_alts and len(q.alts) == 5 and it["thin"]:
                    continue  # traço depois da E (fim de coluna)
                q.fig = True
                q.figs.append((it["page"], round(it["x0"]), round(it["y0"]), round(it["x1"]), round(it["y1"])))
            elif mode == "between" and preamble_for is not None and not it["thin"]:
                preamble_fig = True
            continue

        text = it["text"].strip()
        flat = _SPACES.sub("", text)
        m = _HEADER.match(flat)
        if m:
            finish()
            number = int(m.group(1))
            if number > 5:
                lang = None
            q = _Q(number, lang if number <= 5 else None, it)
            mode = "question"
            if preamble_for is not None and preamble_for[0] <= number <= preamble_for[1]:
                q.preamble = list(preamble)
                q.fig = preamble_fig
            elif preamble_for is not None:
                preamble, preamble_for, preamble_fig = [], None, False
            continue

        ml = _LANG.search(flat)
        if ml:
            finish()
            lang = "ingles" if ml.group(1).lower().startswith("ingl") else "espanhol"
            mode = "between"
            preamble, preamble_for, preamble_fig = [], None, False
            continue
        if _SECTION.match(flat) and not _PREAMBLE.match(flat):
            finish()
            mode = "between"
            continue
        if _AREA_TITLE.search(flat) and it["size"] >= 10.5 and flat.upper() == flat:
            finish()
            mode = "between"
            continue
        if _STOP.match(flat):
            finish()
            mode = "ignore"
            preamble, preamble_for, preamble_fig = [], None, False
            continue
        if _PREAMBLE.match(flat) and (q is None or in_alts):
            finish()
            nums = [int(n) for n in re.findall(r"\d+", text)]
            preamble_for = (min(nums), max(nums)) if nums else None
            preamble, preamble_fig = [], False
            mode = "between"
            continue

        if q is None:
            if mode == "between" and preamble_for is not None:
                preamble.append(it)
            else:
                orphans += 1
            continue

        q.problems.extend(it["problems"])
        label = _LABEL.match(it["first"]) if it["nspans"] >= 1 else None
        want = "ABCDE"[len(q.alts)] if len(q.alts) < 5 else None
        if label and label.group(1) == want and (
            it.get("label_font", True)
        ):
            rest = dict(it)
            rest["text"] = it["text"][len(it["first"]):] if it["text"].startswith(it["first"]) \
                else it["text"][1:]
            q.alts.append([rest])
            in_alts = True
            q.last_alt_line = it
            continue
        if in_alts:
            last = q.last_alt_line
            if len(q.alts) < 5:
                q.alts[-1].append(it)
                q.last_alt_line = it
                continue
            same = it["page"] == last["page"] and it["col"] == last["col"]
            cont = same and -6 <= it["y0"] - last["y1"] < 5
            split_alt = (not same) and it["y0"] < 100 and last["y1"] >= 722
            if cont or split_alt:
                q.alts[-1].append(it)
                q.last_alt_line = it
                continue
            # texto solto depois da E: fim da questão
            finish()
            if _PREAMBLE.match(flat):
                preamble_for = None
            orphans += 1
            mode = "between"
            continue
        q.stmt.append(it)
    finish()
    if orphans:
        warnings.append(f"{orphans} linha(s) soltas fora de questão (títulos, redação)")
    return questions, warnings


def validate(questions):
    """Problemas de consistência do caderno (lista de textos; vazia se tudo bate)."""
    problems = []
    seen = {}
    for q in questions:
        key = (q["number"], q["language"])
        if key in seen:
            problems.append(f"questão repetida: {key}")
        seen[key] = q
        if q["area"] is None:
            problems.append(f"número fora das faixas: {q['number']}")
    numbers = sorted({q["number"] for q in questions})
    if numbers:
        missing = sorted(set(range(numbers[0], numbers[-1] + 1)) - set(numbers))
        if missing:
            problems.append(f"números ausentes: {missing}")
    return problems


# ---------------------------------------------------------------------------
# Comandos
# ---------------------------------------------------------------------------

def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_name(name):
    """Só caderno de questões do INEP ("PV"); gabarito (`GB`) é recusado."""
    if not re.fullmatch(r"20\d\d_PV_[A-Za-z0-9_]+\.pdf", name) or "_GB_" in name:
        raise ValueError(f"arquivo recusado (só cadernos de questões 'PV'): {name}")
    return name


def download(names, cache=CACHE):
    os.makedirs(cache, exist_ok=True)
    for name in names:
        safe_name(name)
        path = os.path.join(cache, name)
        if os.path.exists(path):
            continue
        req = urllib.request.Request(BASE_URL + name, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=120) as r:  # noqa: S310 (https fixo do INEP)
            data = r.read()
        if not data.startswith(b"%PDF"):
            raise ValueError(f"{name}: a resposta não é um PDF")
        with open(path, "wb") as f:
            f.write(data)
        print(f"baixado: {name} ({len(data)} bytes)")
        time.sleep(1)


def extract_edition(key, cache=CACHE):
    year, variant, names = EDITIONS[key]
    questions, warnings, files = [], [], []
    for name in names:
        safe_name(name)
        path = os.path.join(cache, name)
        qs, w = parse(pages_from_pdf(path))
        questions += qs
        warnings += [f"{name}: {x}" for x in w]
        with open(path, "rb") as f:
            pages = len(re.findall(rb"/Type\s*/Page[^s]", f.read()))
        files.append({"name": name, "url": BASE_URL + name, "sha256": _sha256(path),
                      "bytes": os.path.getsize(path), "pages": pages})
    for q in questions:
        q.pop("_figs", None)  # só para depuração (`parse`)
        if q["hasFigure"] or not q["isComplete"]:
            q["statement"], q["alternatives"] = "", []  # fora do acervo: não guarda o texto
    questions.sort(key=lambda q: (q["number"], q["language"] or ""))
    problems = validate(questions)
    return {
        "edition": key, "year": year, "variant": variant, "source": "enem",
        "files": files, "questions": questions,
    }, warnings + problems


def dump(doc):
    def j(v):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"))

    head = {k: doc[k] for k in ("edition", "year", "variant", "source")}
    lines = [j(q) for q in doc["questions"]]
    return (
        "{" + ",".join(f'"{k}":{j(v)}' for k, v in head.items())
        + f',"files":{j(doc["files"])},"questions":[\n' + ",\n".join(lines) + "\n]}\n"
    )


def write_manifest(docs, out_dir=EXTRACTED):
    path = os.path.join(out_dir, "manifest.json")
    manifest = {"note": "Só cadernos de questões (PV) do INEP; o gabarito nunca é baixado.",
                "editions": {}}
    for key, doc in sorted(docs.items()):
        manifest["editions"][key] = {"year": doc["year"], "variant": doc["variant"],
                                      "files": doc["files"]}
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("command", choices=("download", "extract"))
    p.add_argument("--edition", action="append", choices=sorted(EDITIONS),
                   help="padrão: todas")
    p.add_argument("--cache-dir", default=CACHE)
    p.add_argument("--out-dir", default=EXTRACTED)
    args = p.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    keys = args.edition or sorted(EDITIONS)
    if args.command == "download":
        for k in keys:
            download(EDITIONS[k][2], args.cache_dir)
        return 0
    os.makedirs(args.out_dir, exist_ok=True)
    docs = {}
    existing = os.path.join(args.out_dir, "manifest.json")
    if os.path.exists(existing):
        with open(existing, encoding="utf-8") as f:
            for k, v in json.load(f)["editions"].items():
                docs[k] = {"year": v["year"], "variant": v["variant"], "files": v["files"]}
    for k in keys:
        doc, problems = extract_edition(k, args.cache_dir)
        docs[k] = doc
        with open(os.path.join(args.out_dir, f"{k}.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write(dump(doc))
        qs = doc["questions"]
        ok = [q for q in qs if q["isComplete"] and not q["hasFigure"]]
        print(f"{k}: {len(qs)} questões lidas, {len(ok)} sem figura e completas, "
              f"{sum(q['hasFigure'] for q in qs)} com figura, "
              f"{sum(not q['isComplete'] for q in qs)} incompletas")
        for pr in problems:
            print(f"  AVISO {pr}")
    write_manifest(docs, args.out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
