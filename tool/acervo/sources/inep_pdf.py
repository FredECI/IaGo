"""Adaptador do ENEM a partir dos cadernos de prova em PDF do INEP (somente leitura de arquivos).

Não acessa a rede: lê `tool/acervo/extracted/<edição>.json`, gerado por `extract_inep.py` a
partir do caderno de questões oficial (o gabarito nunca é baixado). Cada questão traz
`hasFigure` e `isComplete`; as que têm figura ou vieram incompletas entram como
exclusões (para o relatório contar), sem texto.
"""

import json
import os
from typing import Callable, Iterator

from .base import RawQuestion, SourceAdapter

EXTRACTED_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "extracted"
)
_VARIANT_SLUG = {"ppl": "ppl", "reaplicacao": "reap"}
_SUBJECT = {"ingles": "Inglês", "espanhol": "Espanhol"}


def question_id(year, variant, number, language):
    parts = ["enem", str(year)]
    if variant:
        parts.append(_VARIANT_SLUG[variant])
    parts.append(str(number))
    if language:
        parts.append(language)
    return "-".join(parts)


class InepPdfAdapter(SourceAdapter):
    id = "enem"
    allowed_prefix = "https://download.inep.gov.br/"  # não usado: o adaptador não acessa a rede
    extracted_dir = EXTRACTED_DIR

    def iter_questions(
        self, get_json: Callable[[str], object], log: Callable[[str], None]
    ) -> Iterator[RawQuestion]:
        if not os.path.isdir(self.extracted_dir):
            return
        for name in sorted(os.listdir(self.extracted_dir)):
            if not name.endswith(".json") or name == "manifest.json":
                continue
            with open(os.path.join(self.extracted_dir, name), encoding="utf-8") as f:
                doc = json.load(f)
            year, variant = int(doc["year"]), doc.get("variant")
            if variant is not None and variant not in _VARIANT_SLUG:
                raise ValueError(f"{name}: variante desconhecida: {variant!r}")
            count = 0
            for q in doc["questions"]:
                number, language = int(q["number"]), q.get("language")
                if language is not None and language not in _SUBJECT:
                    raise ValueError(f"{name}: língua inesperada: {language!r}")
                exclusions = []
                if q.get("hasFigure"):
                    exclusions.append("imagem_no_enunciado")
                if not q.get("isComplete"):
                    exclusions.append("extracao_incompleta")
                text = q.get("statement", "") + " " + " ".join(q.get("alternatives", []))
                if "gabarito" in text.lower():
                    # a palavra é vetada em todo o asset (CA-F5), mesmo em sentido comum
                    exclusions.append("palavra_gabarito")
                subject = _SUBJECT.get(language)
                if q["area"] == "mathematics":
                    subject = "Matemática"
                count += 1
                yield RawQuestion(
                    source=self.id, edition=year, number=number,
                    id=question_id(year, variant, number, language),
                    area=q["area"], statement=q.get("statement", ""),
                    alternatives=list(q.get("alternatives", [])), subject=subject,
                    exclusions=exclusions, variant=variant,
                )
            log(f"ENEM {doc['edition']} (PDF do INEP): {count} questões lidas")
