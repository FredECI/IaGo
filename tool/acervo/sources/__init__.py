"""Registro explícito de adaptadores (sem importação dinâmica a partir de dados)."""

from .enem_dev import EnemDevAdapter

ADAPTERS = {
    "enem": EnemDevAdapter,
}
