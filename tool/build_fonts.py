"""Gera as fontes estáticas do IaGo a partir da Inter variável (licença OFL).

A mesma fonte é usada no app e no PDF, então ela precisa cobrir acentos,
símbolos de matemática/química (², √, π, ≤, H₂O, →) e funcionar offline.

Uso (precisa do uv instalado):
    uv run --with fonttools -- python tool/build_fonts.py <Inter[opsz,wght].ttf>

A fonte variável vem de https://github.com/google/fonts/tree/main/ofl/inter
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# Blocos Unicode mantidos no recorte (subset).
UNICODE_RANGES = [
    "U+0020-007E",  # Latim básico
    "U+00A0-00FF",  # Latim-1 (acentos do português, ², °, ½)
    "U+0100-017F",  # Latim estendido A
    "U+0300-036F",  # Diacríticos combinantes (texto colado de PDF)
    "U+0370-03FF",  # Grego (π, Δ, θ, λ)
    "U+2000-206F",  # Pontuação geral (—, “ ”, …)
    "U+2070-209F",  # Sobrescritos e subscritos (x², H₂O)
    "U+20A0-20CF",  # Moedas
    "U+2100-214F",  # Símbolos tipo letra
    "U+2150-218F",  # Frações
    "U+2190-21FF",  # Setas
    "U+2200-22FF",  # Operadores matemáticos
    "U+2300-23FF",  # Técnicos diversos
    "U+25A0-25FF",  # Formas geométricas
]

WEIGHTS = {"Regular": 400, "Medium": 500, "Bold": 700}


def main() -> None:
    source = Path(sys.argv[1])
    out_dir = Path(__file__).resolve().parent.parent / "assets" / "fonts"
    out_dir.mkdir(parents=True, exist_ok=True)

    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.hinting = False
    options.notdef_outline = True
    unicodes = subset.parse_unicodes(",".join(UNICODE_RANGES))

    for style, weight in WEIGHTS.items():
        font = TTFont(source)
        static = instancer.instantiateVariableFont(font, {"wght": weight, "opsz": 14})
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=unicodes)
        subsetter.subset(static)
        target = out_dir / f"Inter-{style}.ttf"
        static.save(target)
        print(f"{target.name}: {target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
