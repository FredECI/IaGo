"""Contrato dos adaptadores de fonte do acervo.

Cada fonte tem um adaptador que:
  1. sabe listar as questões da fonte (``iter_questions``);
  2. descarta qualquer campo de resposta ANTES de gravar no cache (``sanitize``);
  3. devolve ``RawQuestion`` já no formato comum, sem nenhum campo de resposta.

Acrescentar uma fonte nova = novo arquivo aqui + uma linha em ``sources/__init__.py``
+ uma entrada em ``sources.json``. O script principal não muda.
"""

from dataclasses import dataclass, field
from typing import Callable, Iterator, List, Optional

AREAS = ("languages", "humanities", "naturalSciences", "mathematics")


@dataclass
class RawQuestion:
    source: str
    edition: int  # ano da prova (ou outra chave de agrupamento da fonte)
    number: int
    id: str  # estável, começa pelo id da fonte
    area: str  # um de AREAS
    statement: str
    alternatives: List[str]
    subject: Optional[str] = None  # só quando a fonte garante; senão a A2 classifica
    exclusions: List[str] = field(default_factory=list)  # motivos decididos pelo adaptador


class SourceAdapter:
    id: str = ""
    allowed_prefix: str = ""  # o fetcher só aceita URLs que começam assim

    def __init__(self, covered=None):
        # codepoints com glifo na fonte do app (ou None se desconhecido)
        self.covered = covered

    def sanitize(self, url: str, data):
        """Remove campos de resposta do JSON baixado. Chamado antes do cache."""
        return data

    def iter_questions(
        self, get_json: Callable[[str], object], log: Callable[[str], None]
    ) -> Iterator[RawQuestion]:
        raise NotImplementedError
