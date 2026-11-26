"""Testes da extração dos PDFs do INEP, do adaptador `inep_pdf` e da deduplicação (BM12, BM15).

Sem rede e sem pymupdf: a análise do texto roda sobre itens sintéticos.
"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ACERVO = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(ACERVO))
sys.path.insert(0, ACERVO)

import extract_inep as ex  # noqa: E402
from dedupe import dedupe, fingerprint, normalize  # noqa: E402
from sources.base import RawQuestion  # noqa: E402
from sources.inep_pdf import InepPdfAdapter, question_id  # noqa: E402


def t(y0, text, x0=23.0, x1=270.0, size=10.0, label=False, nspans=1):
    return {"k": "t", "x0": x0, "y0": y0, "x1": x1, "y1": y0 + 12, "text": text, "size": size,
            "base": y0 + 10, "first": text.split(" ")[0] + " " if label else text,
            "nspans": 2 if label else nspans, "problems": [], "label_font": label}


def fig(y0, y1, x0=40.0, x1=250.0, thin=False):
    return {"k": "f", "x0": x0, "y0": y0, "x1": x1, "y1": y1, "thin": thin}


def page(items, split=None):
    return {"split": split, "items": items}


def alts(y0, texts):
    return [t(y0 + 14 * i, f"{'ABCDE'[i]} {x}", label=True) for i, x in enumerate(texts)]


FIVE = ["um", "dois", "três", "quatro", "cinco"]


class ParseTest(unittest.TestCase):
    def one(self, items, split=None):
        qs, _ = ex.parse([page(items, split)])
        return qs

    def test_basic_question_with_five_alternatives(self):
        qs = self.one([t(76, "Questão 91"), t(94, "Enunciado de teste."), t(120, "Qual?")]
                      + alts(140, FIVE))
        self.assertEqual(len(qs), 1)
        q = qs[0]
        self.assertEqual((q["number"], q["area"], q["isComplete"], q["hasFigure"]),
                         (91, "naturalSciences", True, False))
        self.assertEqual(q["alternatives"], FIVE)
        self.assertIn("Enunciado de teste.", q["statement"])

    def test_header_with_spaced_letters_and_case(self):
        qs = self.one([t(76, "Q U ES T ã O 136 "), t(94, "x"), *alts(110, FIVE)])
        self.assertEqual([q["number"] for q in qs], [136])
        self.assertEqual(qs[0]["area"], "mathematics")

    def test_alternative_needs_label_font(self):
        # "A noção..." no enunciado não é a alternativa A (a fonte do rótulo é outra)
        stmt = t(94, "A noção de eudaimonia", nspans=3)
        stmt["first"] = "A "
        qs = self.one([t(76, "Questão 50"), stmt, *alts(120, FIVE)])
        self.assertEqual(qs[0]["alternatives"], FIVE)
        self.assertTrue(qs[0]["statement"].startswith("A noção"))

    def test_figure_marks_question_but_header_rule_does_not(self):
        header_rule = fig(81, 84, x0=100, x1=270, thin=True)
        head = t(76, "Questão 92", x1=90)
        qs = self.one([head, header_rule, t(94, "x"), *alts(110, FIVE)])
        self.assertFalse(qs[0]["hasFigure"])
        qs = self.one([head, t(94, "x"), fig(100, 109), *alts(110, FIVE)])
        self.assertTrue(qs[0]["hasFigure"])

    def test_thin_line_after_last_alternative_is_ignored(self):
        qs = self.one([t(76, "Questão 93"), t(94, "x"), *alts(110, FIVE),
                       fig(190, 192, x0=23, x1=270, thin=True)])
        self.assertFalse(qs[0]["hasFigure"])

    def test_last_alternative_continues_on_next_line(self):
        items = [t(76, "Questão 94"), t(94, "x"), *alts(110, FIVE[:4] + ["cinco e"]),
                 t(110 + 14 * 4 + 12, "continuação.", x0=35)]
        qs = self.one(items)
        self.assertEqual(qs[0]["alternatives"][4], "cinco e continuação.")

    def test_incomplete_when_alternative_missing(self):
        qs = self.one([t(76, "Questão 95"), t(94, "x"), *alts(110, FIVE[:3])])
        self.assertFalse(qs[0]["isComplete"])

    def test_foreign_language_variants_and_numbers_reset(self):
        items = [t(60, "Questões de 01 a 05 (opção inglês)"), t(76, "Questão 01"), t(94, "a"),
                 *alts(110, FIVE), t(200, "Questões de 01 a 05 (opção espanhol)"),
                 t(216, "Questão 01"), t(234, "b"), *alts(250, FIVE),
                 t(330, "Questão 06"), t(348, "c"), *alts(364, FIVE)]
        qs = self.one(items)
        self.assertEqual([(q["number"], q["language"]) for q in qs],
                         [(1, "ingles"), (1, "espanhol"), (6, None)])
        self.assertNotIn("repetida", " ".join(ex.validate(qs)))

    def test_shared_text_goes_to_the_questions_it_names(self):
        items = [t(76, "Texto para as Questões de 06 a 07."), t(94, "Texto base."),
                 t(300, "Questão 06"), t(320, "Pergunta 6."), *alts(340, FIVE),
                 t(430, "Questão 07"), t(450, "Pergunta 7."), *alts(470, FIVE),
                 t(560, "Questão 08"), t(580, "Outra."), *alts(600, FIVE)]
        qs = self.one(items)
        self.assertTrue(qs[0]["statement"].startswith("Texto base."))
        self.assertTrue(qs[1]["statement"].startswith("Texto base."))
        self.assertEqual(qs[2]["statement"], "Outra.")

    def test_essay_prompt_after_last_question_is_not_appended(self):
        items = [t(76, "Questão 45"), t(94, "x"), *alts(110, FIVE),
                 t(300, "PROPOSTA DE REDAÇÃO"), t(320, "Texto da redação")]
        qs = self.one(items)
        self.assertEqual(qs[0]["alternatives"][4], "cinco")

    def test_script_problem_marks_incomplete(self):
        item = t(94, "x")
        item["problems"] = ["indice_nao_representavel"]
        qs = self.one([t(76, "Questão 96"), item, *alts(110, FIVE)])
        self.assertFalse(qs[0]["isComplete"])

    def test_private_use_glyph_marks_incomplete(self):
        qs = self.one([t(76, "Questão 97"), t(94, "reação  final"), *alts(110, FIVE)])
        self.assertFalse(qs[0]["isComplete"])

    def test_paragraphs_verses_and_credits(self):
        items = [t(76, "Questão 50"),
                 t(94, "Primeira linha de verso", x1=150), t(106, "Segunda linha", x1=120),
                 t(130, "CREDITO, A. Disponível em:", x0=100, size=8),
                 t(141, "www.x.com.", x0=150, size=8),
                 t(160, "Pergunta?"), *alts(180, FIVE)]
        qs = self.one(items)
        self.assertEqual(qs[0]["statement"],
                         "Primeira linha de verso\nSegunda linha\n\n"
                         "CREDITO, A. Disponível em: www.x.com.\n\nPergunta?")

    def test_margin_line_numbers_are_dropped(self):
        nums = [t(94 + 12 * i, str(i + 1), x0=111, x1=116) for i in range(4)]
        items = [t(76, "Questão 50"), *nums, t(150, "Texto."), *alts(170, FIVE)]
        self.assertEqual(self.one(items)[0]["statement"], "Texto.")

    def test_repeated_hyphen_at_line_break(self):
        lines = [t(94, "cultura Afro-"), t(106, "-Brasileira serão")]
        qs = self.one([t(76, "Questão 50"), *lines, *alts(130, FIVE)])
        self.assertEqual(qs[0]["statement"], "cultura Afro-Brasileira serão")

    def test_two_columns_are_read_left_then_right(self):
        left = [t(76, "Questão 91", x0=23, x1=270), t(94, "esquerda", x1=270), *alts(110, FIVE)]
        right = [t(76, "Questão 92", x0=290, x1=537), t(94, "direita", x0=290, x1=537),
                 *[dict(a, x0=290, x1=537) for a in alts(110, FIVE)]]
        qs = self.one(right + left, split=280)
        self.assertEqual([q["number"] for q in qs], [91, 92])

    def test_validate_finds_gaps_and_repeats(self):
        base = {"language": None, "area": "mathematics"}
        qs = [dict(base, number=136), dict(base, number=139), dict(base, number=139)]
        out = " ".join(ex.validate(qs))
        self.assertIn("repetida", out)
        self.assertIn("137", out)


class SafetyTest(unittest.TestCase):
    def test_answer_key_files_are_refused(self):
        for name in ("2025_GB_impresso_D1_CD1.pdf", "2024_GB_reaplicacao_PPL_D1_CD1.pdf",
                     "../2025_PV_impresso_D1_CD1.pdf", "gabarito.pdf"):
            with self.assertRaises(ValueError, msg=name):
                ex.safe_name(name)
        self.assertEqual(ex.safe_name("2025_PV_impresso_D1_CD1.pdf"),
                         "2025_PV_impresso_D1_CD1.pdf")

    def test_every_configured_file_is_a_question_booklet(self):
        for _, _, names in ex.EDITIONS.values():
            for n in names:
                ex.safe_name(n)

    def test_area_ranges(self):
        self.assertEqual([ex.area_of(n) for n in (1, 45, 46, 90, 91, 135, 136, 180, 181)],
                         ["languages", "languages", "humanities", "humanities",
                          "naturalSciences", "naturalSciences", "mathematics", "mathematics",
                          None])


class AdapterTest(unittest.TestCase):
    def run_adapter(self, questions, year=2024, variant=None):
        with tempfile.TemporaryDirectory() as tmp:
            doc = {"edition": f"{year}", "year": year, "variant": variant, "source": "enem",
                   "files": [], "questions": questions}
            with open(os.path.join(tmp, f"{year}.json"), "w", encoding="utf-8") as f:
                json.dump(doc, f)
            with open(os.path.join(tmp, "manifest.json"), "w", encoding="utf-8") as f:
                f.write("{}")
            ad = InepPdfAdapter()
            ad.extracted_dir = tmp
            return list(ad.iter_questions(None, lambda m: None))

    def q(self, number, **kw):
        base = {"number": number, "area": "humanities", "language": None, "statement": "e",
                "alternatives": FIVE, "hasFigure": False, "isComplete": True}
        base.update(kw)
        return base

    def test_ids_follow_the_catalog_pattern(self):
        self.assertEqual(question_id(2024, None, 136, None), "enem-2024-136")
        self.assertEqual(question_id(2024, None, 3, "ingles"), "enem-2024-3-ingles")
        self.assertEqual(question_id(2024, "ppl", 140, None), "enem-2024-ppl-140")
        self.assertEqual(question_id(2025, "reaplicacao", 140, None), "enem-2025-reap-140")

    def test_figure_incomplete_and_gabarito_word_become_exclusions(self):
        out = self.run_adapter([
            self.q(46), self.q(47, hasFigure=True, statement="", alternatives=[]),
            self.q(48, isComplete=False), self.q(49, statement="de alto gabarito")])
        self.assertEqual([r.exclusions for r in out],
                         [[], ["imagem_no_enunciado"], ["extracao_incompleta"],
                          ["palavra_gabarito"]])

    def test_subject_only_where_the_source_guarantees_it(self):
        out = self.run_adapter([
            self.q(1, area="languages", language="ingles"),
            self.q(136, area="mathematics"), self.q(46)], variant="ppl")
        self.assertEqual([(r.subject, r.id, r.variant) for r in out],
                         [("Inglês", "enem-2024-ppl-1-ingles", "ppl"),
                          ("Matemática", "enem-2024-ppl-136", "ppl"),
                          (None, "enem-2024-ppl-46", "ppl")])


def rq(i, statement, source="enem", edition=2024, variant=None, alts=None):
    return RawQuestion(source=source, edition=edition, number=i,
                       id=f"{source}-{edition}-{i}", area="humanities", statement=statement,
                       alternatives=alts or list(FIVE), variant=variant)


class DedupeTest(unittest.TestCase):
    def test_normalization_ignores_accents_case_and_punctuation(self):
        self.assertEqual(normalize("  Água,  À  Vista! "), "agua a vista")
        self.assertEqual(fingerprint(rq(1, "Água, é Vida.")), fingerprint(rq(2, "agua e vida")))

    def test_exact_duplicate_keeps_the_earliest(self):
        a, b = rq(5, "Mesmo texto.", edition=2024), rq(3, "mesmo   TEXTO", edition=2025)
        kept, removed, protected, _ = dedupe([b, a], {"enem": 0})
        self.assertEqual([q.id for q in kept], [a.id])
        self.assertEqual([(q.id, other) for q, other in removed], [(b.id, a.id)])
        self.assertEqual(protected, [])

    def test_variant_ranks_after_regular_in_the_same_year(self):
        a = rq(5, "Igual.", variant=None)
        b = rq(5, "Igual.", variant="ppl")
        b.id = "enem-2024-ppl-5"
        kept, removed, _, _ = dedupe([b, a], {"enem": 0})
        self.assertEqual([q.id for q in kept], [a.id])
        self.assertEqual(removed[0][0].id, b.id)

    def test_published_ids_are_never_removed(self):
        a, b = rq(1, "Igual.", edition=2010), rq(2, "Igual.", edition=2011)
        kept, removed, protected, _ = dedupe([a, b], {"enem": 0}, published=[b.id])
        self.assertEqual(len(kept), 2)
        self.assertEqual(removed, [])
        self.assertEqual([(q.id, o) for q, o in protected], [(b.id, a.id)])

    def test_source_order_wins_before_year(self):
        a = rq(1, "Igual.", source="outra", edition=2000)
        b = rq(1, "Igual.", source="enem", edition=2020)
        kept, removed, _, _ = dedupe([a, b], {"enem": 0, "outra": 1})
        self.assertEqual([q.id for q in kept], [b.id])

    def test_near_duplicate_is_only_flagged(self):
        head = "x" * 210
        a, b = rq(1, head + " fim um"), rq(2, head + " fim dois")
        kept, removed, _, near = dedupe([a, b], {"enem": 0})
        self.assertEqual(len(kept), 2)
        self.assertEqual(removed, [])
        self.assertEqual(near, [(a.id, b.id)])

    def test_different_alternatives_are_not_duplicates(self):
        a = rq(1, "Igual.")
        b = rq(2, "Igual.", alts=["a", "b", "c", "d", "e"])
        self.assertEqual(len(dedupe([a, b], {"enem": 0})[0]), 2)


class ExtractedFilesTest(unittest.TestCase):
    """Os arquivos extraídos em git (CA-BM14 e CA-F5)."""

    def docs(self):
        out = {}
        d = os.path.join(ACERVO, "extracted")
        for name in sorted(os.listdir(d)):
            if name.endswith(".json") and name != "manifest.json":
                with open(os.path.join(d, name), encoding="utf-8") as f:
                    out[name] = json.load(f)
        return out

    def test_manifest_lists_only_question_booklets_with_hash_and_official_link(self):
        with open(os.path.join(ACERVO, "extracted", "manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
        self.assertTrue(manifest["editions"])
        for ed in manifest["editions"].values():
            for fl in ed["files"]:
                ex.safe_name(fl["name"])
                self.assertTrue(fl["url"].startswith(ex.BASE_URL))
                self.assertRegex(fl["sha256"], r"^[0-9a-f]{64}$")

    def test_extracted_questions_are_consistent_and_have_no_answer_key(self):
        docs = self.docs()
        self.assertTrue(docs)
        for name, doc in docs.items():
            text = json.dumps(doc["questions"], ensure_ascii=False).lower()
            for bad in ("gabarito", "correctalternative", "iscorrect", "tx_gabarito"):
                self.assertNotIn(bad, text.replace("alto gabarito", ""), f"{name}: {bad}")
            self.assertEqual(ex.validate(doc["questions"]), [], name)
            for q in doc["questions"]:
                self.assertEqual(q["area"], ex.area_of(q["number"]))
                if q["isComplete"] and not q["hasFigure"]:
                    self.assertEqual(len(q["alternatives"]), 5, f"{name} {q['number']}")
                    self.assertTrue(q["statement"].strip())
                    self.assertTrue(all(a.strip() for a in q["alternatives"]))
                    self.assertNotRegex(q["statement"], r"ENE[MN]\d{4}")
                else:
                    self.assertEqual((q["statement"], q["alternatives"]), ("", []))

    def test_generated_asset_has_new_editions_all_classified_and_no_answers(self):
        base = os.path.join(REPO, "assets", "acervo", "v2")
        questions = []
        for a in ("languages", "humanities", "naturalSciences", "mathematics"):
            with open(os.path.join(base, f"{a}.json"), encoding="utf-8") as f:
                questions += json.load(f)["questions"]
        new = [q for q in questions if q["year"] >= 2024]
        self.assertGreater(len(new), 400)
        self.assertEqual({q["year"] for q in new}, {2024, 2025, 2026})
        self.assertEqual({q.get("variant") for q in new}, {None, "ppl", "reaplicacao"})
        self.assertTrue(all(q.get("subject") for q in new))
        self.assertEqual(len({q["id"] for q in questions}), len(questions))
        self.assertNotIn("gabarito", json.dumps(new, ensure_ascii=False).lower())


if __name__ == "__main__":
    unittest.main()
