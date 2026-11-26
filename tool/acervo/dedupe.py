"""Deduplicação do acervo (BM15).

- Impressão digital: sha1 do enunciado e das alternativas normalizados (NFC, minúsculas,
  sem acentos, só ``[a-z0-9]`` e espaço simples).
- Duplicata exata: fica a questão da fonte que vem antes no registro e, depois, a de menor
  (ano, variante, número). A outra sai e vai para o relatório. Um id já publicado
  (``ids-v1.txt``) nunca sai: as duas ficam, e o caso é só relatado.
- Quase duplicata (mesmas alternativas e os primeiros 200 caracteres do enunciado iguais):
  só é sinalizada, para revisão humana.
"""

import hashlib
import re
import unicodedata

NEAR_PREFIX = 200
_VARIANT_ORDER = {None: 0, "ppl": 1, "reaplicacao": 2}


def normalize(text):
    text = unicodedata.normalize("NFD", unicodedata.normalize("NFC", text).lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", text)).strip()


def fingerprint(q):
    body = normalize(q.statement) + "\n" + "\n".join(normalize(a) for a in q.alternatives)
    return hashlib.sha1(body.encode("utf-8")).hexdigest()


def near_key(q):
    alts = "\n".join(normalize(a) for a in q.alternatives)
    return normalize(q.statement)[:NEAR_PREFIX] + "\n" + alts


def rank(q, source_order):
    return (
        source_order.get(q.source, len(source_order)), q.edition,
        _VARIANT_ORDER.get(getattr(q, "variant", None), 9), q.number, q.id,
    )


def dedupe(kept, source_order, published=()):
    """Devolve (questões mantidas, duplicatas removidas [(q, id_mantido)],
    duplicatas mantidas por já estarem publicadas [(q, id_outro)], quase duplicatas
    [(id, id)])."""
    published = set(published)
    ordered = sorted(kept, key=lambda q: rank(q, source_order))
    first, removed, protected, drop = {}, [], [], set()
    for q in ordered:
        fp = fingerprint(q)
        other = first.get(fp)
        if other is None:
            first[fp] = q
        elif q.id in published:
            protected.append((q, other.id))
        else:
            removed.append((q, other.id))
            drop.add(q.id)
    survivors = [q for q in kept if q.id not in drop]
    seen, near = {}, []
    for q in sorted(survivors, key=lambda q: rank(q, source_order)):
        key = near_key(q)
        if key in seen and fingerprint(q) != fingerprint(seen[key]):
            near.append((seen[key].id, q.id))
        seen.setdefault(key, q)
    return survivors, removed, protected, near
