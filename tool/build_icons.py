"""Gera os ícones do IaGo (Android, web e favicon) a partir da marca do app.

Quadrado arredondado com degradê índigo → violeta e o livro aberto
(Material Icons `auto_stories_rounded`, licença Apache 2.0) em branco.

Uso (precisa do uv instalado):
    uv run --with pillow -- python tool/build_icons.py <MaterialIcons-Regular.otf>

A fonte fica no SDK do Flutter:
    <flutter>/bin/cache/artifacts/material_fonts/materialicons-regular.otf
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
GLYPH = chr(0xF59C)  # auto_stories_rounded
START = (0x4F, 0x46, 0xE5)  # índigo #4F46E5
END = (0x7C, 0x3A, 0xED)  # violeta #7C3AED


def gradient(size: int) -> Image.Image:
    """Degradê diagonal (canto superior esquerdo → inferior direito)."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(START, END)) + (255,)
    return img


def icon(size: int, font_path: str, *, rounded: bool, glyph_ratio: float) -> Image.Image:
    base = gradient(size)
    if rounded:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size - 1, size - 1), radius=round(size * 0.28), fill=255
        )
        base.putalpha(mask)
    font = ImageFont.truetype(font_path, round(size * glyph_ratio))
    draw = ImageDraw.Draw(base)
    left, top, right, bottom = draw.textbbox((0, 0), GLYPH, font=font)
    x = (size - (right - left)) / 2 - left
    y = (size - (bottom - top)) / 2 - top
    draw.text((x, y), GLYPH, font=font, fill=(255, 255, 255, 255))
    return base


def main() -> None:
    font_path = sys.argv[1]
    outputs = {
        # Android: ícone de lançador (quadrado arredondado).
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, True, 0.56),
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, True, 0.56),
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, True, 0.56),
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, True, 0.56),
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, True, 0.56),
        # Web: ícones do PWA (os "maskable" ocupam o quadrado todo, com o
        # glifo dentro da zona segura) e o favicon da aba.
        "web/icons/Icon-192.png": (192, True, 0.56),
        "web/icons/Icon-512.png": (512, True, 0.56),
        "web/icons/Icon-maskable-192.png": (192, False, 0.46),
        "web/icons/Icon-maskable-512.png": (512, False, 0.46),
        "web/favicon.png": (64, True, 0.6),
    }
    for relative, (size, rounded, ratio) in outputs.items():
        target = ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        icon(size, font_path, rounded=rounded, glyph_ratio=ratio).save(target)
        print(f"{relative}: {size}px")


if __name__ == "__main__":
    main()
