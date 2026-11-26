"""Registro explícito de adaptadores (sem importação dinâmica a partir de dados)."""

from .enem_dev import EnemDevAdapter
from .inep_pdf import InepPdfAdapter

ADAPTERS = {
    "enem": EnemDevAdapter,
    "inep_pdf": InepPdfAdapter,
}
