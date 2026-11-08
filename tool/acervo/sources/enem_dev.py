"""Adaptador do ENEM via api.enem.dev (somente leitura, sem autenticação).

Campos usados: year, index, discipline, language, context,
alternativesIntroduction, alternatives[].text.
Lidos só para filtrar: files, alternatives[].file, imagens em markdown.
Descartados na leitura: correctAlternative e alternatives[].isCorrect.
"""

import html
import re
import unicodedata
from typing import Callable, Iterator

from .base import RawQuestion, SourceAdapter

BASE = "https://api.enem.dev/v1"
FIRST_YEAR = 2009
LAST_YEAR = 2023
PAGE_SIZE = 50

# Campos de resposta: nunca podem chegar ao cache nem ao asset.
_ANSWER_KEYS = frozenset({"correctAlternative", "isCorrect", "gabarito"})

_AREA = {
    "linguagens": "languages",
    "ciencias-humanas": "humanities",
    "ciencias-natureza": "naturalSciences",
    "matematica": "mathematics",
}
_LANGUAGE = {"ingles": "Inglês", "espanhol": "Espanhol"}
_IMAGE_MD = re.compile(r"!\[[^\]]*\]\(")
_IMAGE_HTML = re.compile(r"<\s*img\b", re.IGNORECASE)
_LANG_SLUG = re.compile(r"^[a-z]{2,20}$")


def _strip_answers(value):
    if isinstance(value, dict):
        return {k: _strip_answers(v) for k, v in value.items() if k not in _ANSWER_KEYS}
    if isinstance(value, list):
        return [_strip_answers(v) for v in value]
    return value


_SUB = dict(zip("0123456789+-=()", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎"))
_SUP = dict(zip("0123456789+-=()n", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ"))
_SCRIPT = re.compile(r"<(sub|sup)\b[^>]*>(.*?)</\1\s*>", re.IGNORECASE | re.DOTALL)
_BR = re.compile(r"<br\s*/?>", re.IGNORECASE)
_TAG = re.compile(r"</?[a-zA-Z][^>]*>")
_ESCAPE = re.compile(r"\\([\\`*_{}\[\]#+\-.!~<>|=])")
_HEADER = re.compile(r"(?m)^[ \t]*#{1,6}[ \t]+")
_LINK = re.compile(r"\[([^\]\n]+)\]\([^)\s]*\)")
_LIST = re.compile(r"(?m)^[ \t]*\*[ \t]{2,}(?=\S)")
_BOLD = re.compile(r"\*\*(.+?)\*\*", re.DOTALL)
_ITALIC = re.compile(r"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])")
_UNDERSCORE = re.compile(r"(?<![\w_])_(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?![\w_])")
_BULLET = "•"


def _script(m, covered):
    table = _SUB if m.group(1).lower() == "sub" else _SUP
    inner = m.group(2).strip()
    mapped = "".join(table.get(c, "") for c in inner)
    if inner and len(mapped) == len(inner) and covered is not None \
            and all(ord(c) in covered for c in mapped):
        return mapped
    return inner  # sem glifo na Inter: o texto normal


def clean_markup(text: str, covered=None) -> str:
    """Limpa marcação (HTML e markdown) sem mexer no conteúdo.

    - sub e sup viram caracteres Unicode quando a Inter tem o glifo; senão, o texto normal;
    - as demais tags somem e as entidades HTML são decodificadas;
    - tira **negrito**, *itálico* e _itálico_ (só entre delimitadores: o "_" dentro de
      palavra ou de URL fica), o "#" de cabeçalho, e vira o link [texto](url) em texto;
    - "*   item" vira "• item" (ou "- item" se a Inter não tiver o glifo);
    - desfaz os escapes do markdown; um asterisco solto (nota de rodapé) fica como está;
    - normaliza para NFC, troca NBSP por espaço e arruma os espaços.
    """
    text = unicodedata.normalize("NFC", text).replace("\xa0", " ")
    text = _SCRIPT.sub(lambda m: _script(m, covered), text)
    text = _BR.sub("\n", text)
    text = _TAG.sub("", text)
    text = html.unescape(text).replace("\xa0", " ")
    # Protege os escapes antes de procurar ênfase: um asterisco escapado não é delimitador.
    saved = []

    def keep(m):
        saved.append(m.group(1))
        return chr(0xE000 + len(saved) - 1)

    text = text.replace("\\*\\*", "**")  # negrito escapado e quebrado: vira par solto, removido abaixo
    text = _ESCAPE.sub(keep, text)
    text = _LINK.sub(r"\1", text)
    bullet = _BULLET if covered is not None and ord(_BULLET) in covered else "-"
    text = _LIST.sub(bullet + " ", text)
    text = _BOLD.sub(r"\1", text)
    text = text.replace("**", "")  # par quebrado: sobra só o marcador
    text = _ITALIC.sub(r"\1", text)
    text = _UNDERSCORE.sub(r"\1", text)
    text = _HEADER.sub("", text)
    for i, ch in enumerate(saved):
        text = text.replace(chr(0xE000 + i), ch)
    text = unicodedata.normalize("NFC", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"(?<=\S)[ \t]{2,}(?=\S)", " ", text)
    return text.strip()


class EnemDevAdapter(SourceAdapter):
    id = "enem"
    allowed_prefix = BASE + "/"

    def sanitize(self, url, data):
        return _strip_answers(data)

    def iter_questions(
        self, get_json: Callable[[str], object], log: Callable[[str], None]
    ) -> Iterator[RawQuestion]:
        exams = get_json(f"{BASE}/exams")
        years = sorted(
            {e["year"] for e in exams if FIRST_YEAR <= e.get("year", 0) <= LAST_YEAR}
        )
        for year in years:
            seen = {}  # a API repete itens na fronteira entre páginas: deduplica
            offset = 0
            while True:
                url = f"{BASE}/exams/{year}/questions?limit={PAGE_SIZE}&offset={offset}"
                page = get_json(url)
                for item in page["questions"]:
                    key = (item["index"], item.get("language"))
                    if key in seen:
                        if seen[key] != item:
                            raise ValueError(f"itens diferentes com a mesma chave: {year} {key}")
                        continue
                    seen[key] = item
                if not page["metadata"].get("hasMore"):
                    break
                offset += PAGE_SIZE
            # O "offset" da API segue o número da questão, não a posição, então a paginação
            # perde itens quando há questões de língua estrangeira repetidas. O resumo da
            # edição lista todas as questões; as que faltarem vêm uma a uma.
            summary = get_json(f"{BASE}/exams/{year}")["questions"]
            wanted = {(e["index"], e.get("language")) for e in summary}
            fetched_alone = 0
            alone = set()
            for index, language in sorted(wanted - set(seen), key=lambda k: (k[0], str(k[1]))):
                if language is not None and not _LANG_SLUG.match(str(language)):
                    raise ValueError(f"língua inesperada: {language!r}")
                url = f"{BASE}/exams/{year}/questions/{int(index)}"
                if language is not None:
                    url += f"?language={language}"
                seen[(index, language)] = get_json(url)
                alone.add((index, language))
                fetched_alone += 1
            if set(seen) != wanted:
                raise ValueError(f"ENEM {year}: itens lidos diferem do resumo da edição")
            for key in sorted(seen, key=lambda k: (k[0], str(k[1]))):
                # A API às vezes devolve a língua errada (ou nenhuma) ao pedir uma língua
                # específica: o texto não é confiável, então a questão é excluída.
                bad_language = key in alone and seen[key].get("language") != key[1]
                yield self.normalize(seen[key], language=key[1], bad_language=bad_language)
            log(f"ENEM {year}: {len(seen)} itens ({fetched_alone} buscados um a um)")

    def normalize(self, item: dict, language=None, bad_language=False) -> RawQuestion:
        year = int(item["year"])
        number = int(item["index"])
        if language is None and not bad_language:
            language = item.get("language")
        if language is not None and not _LANG_SLUG.match(str(language)):
            raise ValueError(f"língua inesperada: {language!r}")
        qid = f"enem-{year}-{number}" + (f"-{language}" if language else "")
        area = _AREA.get(item.get("discipline"))
        if area is None:
            raise ValueError(f"disciplina desconhecida em {qid}: {item.get('discipline')!r}")

        context = item.get("context") or ""
        intro = item.get("alternativesIntroduction") or ""
        statement = clean_markup(
            "\n\n".join(p for p in (context, intro) if p.strip()), self.covered
        )
        alts = item.get("alternatives") or []

        exclusions = []
        if bad_language:
            exclusions.append("api_lingua_inconsistente")
        if _IMAGE_MD.search(context) or _IMAGE_MD.search(intro) or _IMAGE_HTML.search(context):
            exclusions.append("imagem_no_contexto")
        if item.get("files"):
            exclusions.append("imagem_em_files")
        if any(a.get("file") for a in alts) or any(
            _IMAGE_MD.search(a.get("text") or "") for a in alts
        ):
            exclusions.append("imagem_em_alternativa")

        subject = None
        if area == "mathematics":
            subject = "Matemática"
        elif language in _LANGUAGE:
            subject = _LANGUAGE[language]

        return RawQuestion(
            source=self.id,
            edition=year,
            number=number,
            id=qid,
            area=area,
            subject=subject,
            statement=statement,
            alternatives=[clean_markup(a.get("text") or "", self.covered) for a in alts],
            exclusions=exclusions,
        )
