"""Testes de QA da A1 (acervo). Sem rede.

Rodar na raiz:  python -I tool/acervo/tests/test_acervo_qa.py
Testes de regressão (nome começa com regressao) cobrem defeitos já corrigidos: reproduzem defeito conhecido
do código de produção e passam a ser regressão quando ele for corrigido.
"""

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ACERVO = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(ACERVO))
sys.path.insert(0, ACERVO)
sys.path.insert(0, HERE)

import build_acervo as ba  # noqa: E402
from fetcher import Fetcher, FetchError  # noqa: E402
from sources.base import RawQuestion  # noqa: E402
from sources.enem_dev import EnemDevAdapter, clean_markup  # noqa: E402
from test_acervo import FakeApi, api_item  # noqa: E402

ASSET = os.path.join(REPO, "assets", "acervo", "acervo-v1.json")
CACHE = os.path.join(REPO, "build", "acervo-cache")
SPEC = os.path.join(REPO, "docs", "specs", "mvp-27-11.md")
REPORT = os.path.join(REPO, "build", "acervo-report.md")
BS = chr(92)

SPEC_NOTICE = (
    "Texto das provas do INEP, reproduzido para uso educacional. Formatação ajustada. "
    "Confira o original em https://www.gov.br/inep/pt-br/areas-de-atuacao/"
    "avaliacao-e-exames-educacionais/enem/provas-e-gabaritos"
)


def load_asset():
    with open(ASSET, encoding="utf-8") as f:
        return json.load(f)


def all_text(q):
    return q["statement"] + "\n" + "\n".join(q["alternatives"])


class OfflineReproducibilityTest(unittest.TestCase):  # CA-F1
    @unittest.skipUnless(os.path.isdir(CACHE) and os.path.exists(ASSET), "sem cache/asset")
    def test_offline_regenerates_identical_asset_and_makes_no_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, rep = os.path.join(tmp, "a.json"), os.path.join(tmp, "r.md")
            cmd = [sys.executable, "-I", os.path.join(ACERVO, "build_acervo.py"),
                   "--offline", "--out", out, "--report", rep]
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=300)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("Pedidos de rede: 0", r.stdout)
            with open(out, "rb") as a, open(ASSET, "rb") as b:
                self.assertEqual(a.read(), b.read())
            with open(rep, "rb") as a, open(REPORT, "rb") as b:
                self.assertEqual(a.read(), b.read())

    def test_offline_with_empty_cache_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            cmd = [sys.executable, "-I", os.path.join(ACERVO, "build_acervo.py"), "--offline",
                   "--cache-dir", os.path.join(tmp, "c"), "--out", os.path.join(tmp, "a.json"),
                   "--report", os.path.join(tmp, "r.md")]
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=60)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse(os.path.exists(os.path.join(tmp, "a.json")))


class ResponseFieldsTest(unittest.TestCase):  # CA-F5
    def test_extra_answer_fields_in_odd_positions_never_reach_asset(self):
        items = [api_item(i) for i in range(1, 6)]
        for it in items:
            it["gabarito"] = "B"
            it["meta"] = {"deep": [{"isCorrect": True, "correctAlternative": "B"}]}
            it["alternatives"][2]["gabarito"] = True
            it["alternatives"][0]["extra"] = {"correctAlternative": "A"}
        fake = FakeApi({2022: items})
        raw = fake.get_json("https://api.enem.dev/v1/exams/2022/questions/1")
        clean = EnemDevAdapter().sanitize("", copy.deepcopy(raw))
        txt = json.dumps(clean)
        for k in ("gabarito", "isCorrect", "correctAlternative"):
            self.assertNotIn(k, txt)

        class F:
            get_json = staticmethod(fake.get_json)

        srcs = ba.load_sources(os.path.join(ACERVO, "sources.json"))
        asset, _, _ = ba.build(srcs, lambda a: F, None, "2026-11-07", log=lambda m: None)
        text = ba.dump_asset(asset)
        self.assertEqual(ba.forbidden_keys(asset), set())
        self.assertFalse(ba.has_forbidden_word(text))
        for k in ("isCorrect", "correctAlternative"):
            self.assertNotIn(k, text)
        for q in asset["questions"]:
            self.assertEqual(set(q), {"id", "source", "year", "number", "area", "subject",
                                      "statement", "alternatives"})

    def test_forbidden_keys_detects_any_case_and_depth(self):
        self.assertEqual(ba.forbidden_keys({"a": [{"b": {"GABARITO": 1}}]}), {"GABARITO"})
        self.assertEqual(ba.forbidden_keys([{"isCorrect": 1}]), {"isCorrect"})

    @unittest.skipUnless(os.path.exists(ASSET), "sem asset")
    def test_generated_asset_has_no_answer_keys_or_license_evidence(self):
        d = load_asset()
        self.assertEqual(ba.forbidden_keys(d), set())
        for s in d["sources"]:
            self.assertNotIn("licenseEvidence", s)
            self.assertNotIn("authorized", s)
        for q in d["questions"]:
            self.assertEqual(set(q) - {"subject"},
                             {"id", "source", "year", "number", "area", "statement", "alternatives"})


class CorruptCacheTest(unittest.TestCase):
    def fetcher(self, tmp, **kw):
        calls = []

        class R:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def read(s, n=-1):
                return b'{"ok": true}'

        def opener(req):
            calls.append(req.full_url)
            return R()

        f = Fetcher(tmp, ["https://api.enem.dev/v1/"], opener=opener, sleep=lambda s: None,
                    clock=lambda: 0.0, **kw)
        return f, calls

    def corrupt(self, f, url, content):
        with open(f._path(url), "w", encoding="utf-8") as fh:
            fh.write(content)

    def test_regressao_offline_corrupt_cache_raises_fetch_error_not_traceback(self):
        # Reprodução: truncar um arquivo de build/acervo-cache e rodar --offline.
        # Esperado: FetchError com mensagem clara. Real: JSONDecodeError (traceback).
        url = "https://api.enem.dev/v1/exams"
        with tempfile.TemporaryDirectory() as tmp:
            f, _ = self.fetcher(tmp, offline=True)
            self.corrupt(f, url, '{"url": "x", "da')
            with self.assertRaises(FetchError):
                f.get_json(url)

    def test_regressao_online_corrupt_cache_is_redownloaded(self):
        # Mesma reprodução, sem --offline. Esperado: tratar como cache ausente e baixar de
        # novo. Real: JSONDecodeError em Fetcher.get_json (fetcher.py, leitura do cache).
        url = "https://api.enem.dev/v1/exams"
        with tempfile.TemporaryDirectory() as tmp:
            f, calls = self.fetcher(tmp)
            self.corrupt(f, url, '{"url": "x", "da')
            self.assertEqual(f.get_json(url), {"ok": True})
            self.assertEqual(calls, [url])

    def test_cache_entry_for_other_url_is_ignored(self):
        url = "https://api.enem.dev/v1/exams"
        with tempfile.TemporaryDirectory() as tmp:
            f, calls = self.fetcher(tmp)
            self.corrupt(f, url, json.dumps({"url": "https://api.enem.dev/v1/other", "data": 1}))
            self.assertEqual(f.get_json(url), {"ok": True})
            self.assertEqual(len(calls), 1)


class PrefixTest(unittest.TestCase):
    def test_urls_outside_prefix_are_refused_without_touching_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            def opener(req):
                raise AssertionError("rede acessada: " + req.full_url)

            f = Fetcher(tmp, ["https://api.enem.dev/v1/"], opener=opener)
            for u in ("https://api.enem.dev.evil.com/v1/exams", "http://api.enem.dev/v1/exams",
                      "https://api.enem.dev/v2/exams", "https://api.enem.dev/v1",
                      "https://evil.com/https://api.enem.dev/v1/", "file:///etc/passwd", ""):
                with self.assertRaises(FetchError, msg=u):
                    f.get_json(u)

    def test_adapter_rejects_weird_language_slug(self):
        with self.assertRaises(ValueError):
            EnemDevAdapter().normalize(api_item(1, language="../x"))


class RegistryTest(unittest.TestCase):  # CA-F3, CA-F4, CA-R
    def base(self):
        with open(os.path.join(ACERVO, "sources.json"), encoding="utf-8") as f:
            return json.load(f)

    def load(self, d):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "s.json")
            with open(p, "w", encoding="utf-8") as f:
                json.dump(d, f)
            return ba.load_sources(p)

    def test_authorized_must_be_boolean_true(self):
        for bad in ("true", 1, None, "yes", False):
            d = self.base()
            d["sources"][0]["authorized"] = bad
            with self.assertRaises(ba.SourceRefused, msg=repr(bad)):
                self.load(d)

    def test_blank_evidence_or_http_link_refused(self):
        for key, val in (("licenseEvidence", "   "), ("officialUrl", "http://x.gov.br"),
                         ("licenseUrl", ""), ("attribution", "")):
            d = self.base()
            d["sources"][0][key] = val
            with self.assertRaises(ba.SourceRefused, msg=key):
                self.load(d)

    def test_script_has_no_source_specific_code(self):
        with open(os.path.join(ACERVO, "build_acervo.py"), encoding="utf-8") as f:
            text = f.read().lower()
        for w in ("enem",):
            self.assertNotIn(w, text)

    def test_no_scraper_imports(self):
        for root, _, files in os.walk(ACERVO):
            for n in files:
                if n.endswith(".py") and not n.startswith("test_"):
                    with open(os.path.join(root, n), encoding="utf-8") as f:
                        t = f.read()
                    for bad in ("bs4", "selenium", "scrapy", "playwright", "requests", "lxml"):
                        self.assertNotRegex(t, r"(?m)^\s*(import|from)\s+" + bad, f"{n}:{bad}")


class MarkupTest(unittest.TestCase):
    def test_stray_asterisks_survive(self):
        self.assertEqual(clean_markup("2 * 3 * 4"), "2 * 3 * 4")
        self.assertEqual(clean_markup("a*b*c"), "a*b*c")
        self.assertEqual(clean_markup("nota (*) aqui"), "nota (*) aqui")
        self.assertEqual(clean_markup("* item solto"), "* item solto")
        self.assertEqual(clean_markup("preço 5 *"), "preço 5 *")

    def test_emphasis_removed(self):
        self.assertEqual(clean_markup("um **forte** e *itálico* ok"), "um forte e itálico ok")

    def test_italic_does_not_span_lines(self):
        t = "linha *um\ndois* fim"
        self.assertEqual(clean_markup(t), t)


class LatexHeuristicTest(unittest.TestCase):
    def raw(self, st):
        return RawQuestion("enem", 2022, 1, "enem-2022-1", "mathematics", st, list("abcde"))

    def test_currency_not_latex(self):
        for t in ("R$ 10 e US$ 20", "custa R$10,00 e R$20,00", "US$5 ou US$6", "$5 e $6",
                  "R$ 1,50 por kg, R$ 3,00 por 2 kg"):
            self.assertNotIn("formula_latex", ba.exclusion_reasons(self.raw(t), None), t)

    def test_regressao_escaped_markdown_bracket_is_not_latex(self):
        # Os 72 casos de formula_latex do acervo real sao todos de "\[ ... \]" (colchete
        # escapado do markdown, usado como reticencias em citacoes): falso positivo 100%.
        # Local: build_acervo.py, _LATEX (alternativa \\[(\[]).
        t = "a metade dos atos, mas " + BS + "[o livre-arbitrio" + BS + "] nos permite"
        self.assertNotIn("formula_latex", ba.exclusion_reasons(self.raw(t), None))
        t2 = "Esses chopes dourados  " + BS + "[..." + BS + "]   quando a geracao"
        self.assertNotIn("formula_latex", ba.exclusion_reasons(self.raw(t2), None))

    def test_real_latex_still_excluded(self):
        for t in (BS + "frac{a}{b}", "$x^2$", BS + "(x" + BS + ")", "$$x$$", "valor " + BS + "sqrt{2}"):
            self.assertIn("formula_latex", ba.exclusion_reasons(self.raw(t), None), t)


@unittest.skipUnless(os.path.exists(ASSET), "sem asset")
class AssetContentTest(unittest.TestCase):  # CA-B2, CA-B7, CA-F6
    def test_notice_is_exactly_spec_text(self):
        d = load_asset()
        self.assertEqual(d["sources"][0]["notice"], SPEC_NOTICE)
        if os.path.exists(SPEC):
            with open(SPEC, encoding="utf-8") as f:
                spec = f.read()
            m = re.search(r'"notice": "([^"]+)"', spec)
            self.assertIsNotNone(m)
            self.assertEqual(d["sources"][0]["notice"], m.group(1))

    def test_no_license_claims(self):
        d = load_asset()
        blob = json.dumps(d["sources"], ensure_ascii=False).lower()
        for w in ("sem alteração", "sem alteracao", "licenciado sob", "domínio público"):
            self.assertNotIn(w, blob)
        self.assertNotIn("cc by", d["sources"][0]["notice"].lower())

    def test_counts_and_areas(self):
        qs = load_asset()["questions"]
        self.assertGreaterEqual(len(qs), 1000)
        self.assertEqual(len({q["id"] for q in qs}), len(qs))
        by_area = {}
        for q in qs:
            by_area[q["area"]] = by_area.get(q["area"], 0) + 1
            self.assertRegex(q["id"], r"^enem-\d{4}-\d+(-[a-z]+)?$")
            self.assertTrue(all(isinstance(a, str) and a.strip() for a in q["alternatives"]))
            self.assertTrue(q["statement"].strip())
        self.assertEqual(set(by_area), {"languages", "humanities", "naturalSciences", "mathematics"})
        self.assertTrue(all(n >= 100 for n in by_area.values()), by_area)

    def test_no_images_left(self):
        for q in load_asset()["questions"]:
            t = all_text(q)
            self.assertNotRegex(t, r"!\[[^\]]*\]\(", q["id"])
            self.assertNotRegex(t, r"(?i)<img", q["id"])

    def test_questions_sorted_deterministically(self):
        qs = load_asset()["questions"]
        keys = [(q["source"], q["year"], q["number"], q["id"]) for q in qs]
        self.assertEqual(keys, sorted(keys))

    def test_regressao_no_markdown_escapes_left(self):
        # enem-2010-41 (utimas\_noticias.php), enem-2010-49, enem-2012-91-espanhol,
        # enem-2012-125 (\*), enem-2012-161 (1 3 \_ 9 8 2 0 7): a barra aparece na tela.
        # Causa: clean_markup (sources/enem_dev.py) nao remove escapes do markdown.
        bad = [q["id"] for q in load_asset()["questions"]
               if re.search(re.escape(BS) + r"[_*\[\]()#]", all_text(q))]
        self.assertEqual(bad, [])

    def test_regressao_no_html_tags_or_entities_left(self):
        # enem-2010-66 e enem-2012-59 (<sub>2</sub>), enem-2019-2-ingles (<p>, <strong>,
        # &iacute;): HTML cru no texto da questao.
        bad = [q["id"] for q in load_asset()["questions"]
               if re.search(r"</?[a-zA-Z][^>]*>|&[a-z]+;", all_text(q))]
        self.assertEqual(bad, [])

    def test_regressao_no_markdown_headers_left(self):
        # enem-2017-162: "##### TIPO DE CURVA"
        bad = [q["id"] for q in load_asset()["questions"]
               if re.search(r"(?m)^#{1,6}\s", all_text(q))]
        self.assertEqual(bad, [])

    @unittest.skipUnless(os.path.exists(REPORT), "sem relatório")
    def test_report_has_edition_area_and_reasons(self):  # CA-F6
        with open(REPORT, encoding="utf-8") as f:
            rep = f.read()
        d = load_asset()
        for y in sorted({q["year"] for q in d["questions"]}):
            self.assertRegex(rep, rf"- {y}: \d+ / \d+")
        for a in ("Linguagens", "Humanas", "Natureza", "Matemática"):
            self.assertIn(f"- {a}:", rep)
        m = re.search(r"Lidas: (\d+) \| Aproveitadas: (\d+) \| Excluídas: (\d+)", rep)
        self.assertEqual(int(m.group(2)), len(d["questions"]))
        self.assertEqual(int(m.group(1)), int(m.group(2)) + int(m.group(3)))
        sec = rep.split("primeiro motivo de cada questão; somam o total)")[1].split("##")[0]
        self.assertEqual(sum(int(n) for n in re.findall(r": (\d+)", sec)), int(m.group(3)))


if __name__ == "__main__":
    unittest.main()
