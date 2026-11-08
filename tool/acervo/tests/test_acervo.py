"""Testes do script do acervo. Sem rede: tudo com fixtures locais e relógio falso.

Rodar na raiz:  python -I -m unittest discover -s tool/acervo/tests
"""

import copy
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
ACERVO = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(ACERVO))
sys.path.insert(0, ACERVO)

import build_acervo as ba  # noqa: E402
from fetcher import Fetcher, FetchError  # noqa: E402
from glyphs import covered_codepoints, missing_chars  # noqa: E402
from sources import ADAPTERS  # noqa: E402
from sources.base import RawQuestion, SourceAdapter  # noqa: E402
from sources.enem_dev import BASE, EnemDevAdapter, clean_markup  # noqa: E402

FONT = os.path.join(REPO, "assets", "fonts", "Inter-Regular.ttf")
ASSET = os.path.join(REPO, "assets", "acervo", "acervo-v1.json")


def api_item(index, year=2022, discipline="matematica", language=None, context="Texto.",
             intro="Qual?", alts=None, files=None, correct="B"):
    letters = "ABCDE"
    alts = alts if alts is not None else [f"alt {c}" for c in letters]
    return {
        "title": f"Questão {index} - ENEM {year}",
        "index": index,
        "discipline": discipline,
        "language": language,
        "year": year,
        "context": context,
        "files": files or [],
        "correctAlternative": correct,
        "alternativesIntroduction": intro,
        "alternatives": [
            {"letter": letters[i], "text": t, "file": None, "isCorrect": letters[i] == correct}
            for i, t in enumerate(alts)
        ],
    }


class FakeApi:
    """get_json falso que imita api.enem.dev, incluindo o paginador falho."""

    def __init__(self, items_by_year):
        self.items = items_by_year
        self.calls = []

    def sanitize(self, data):
        return EnemDevAdapter().sanitize("", copy.deepcopy(data))

    def get_json(self, url):
        self.calls.append(url)
        path = url[len(BASE):]
        if path == "/exams":
            return [{"year": y} for y in self.items]
        parts = path.split("?")[0].strip("/").split("/")
        year = int(parts[1])
        items = self.items[year]
        if len(parts) == 2:
            return {"questions": [{"index": i["index"], "language": i["language"]} for i in items]}
        if len(parts) == 4:
            idx = int(parts[3])
            lang = url.split("language=")[1] if "language=" in url else None
            for i in items:
                if i["index"] == idx and i["language"] == lang:
                    return self.sanitize(i)
            raise AssertionError(url)
        q = dict(kv.split("=") for kv in url.split("?")[1].split("&"))
        off, lim = int(q["offset"]), int(q["limit"])
        pool = [i for i in items if i["language"] is None]  # o paginador perde as de língua
        page = pool[off : off + lim]
        return {"questions": self.sanitize(page),
                "metadata": {"hasMore": off + lim < len(pool), "total": len(items)}}


def run_adapter(items_by_year):
    api = FakeApi(items_by_year)
    return list(EnemDevAdapter().iter_questions(api.get_json, lambda m: None)), api


class AdapterTest(unittest.TestCase):
    def test_sanitize_drops_answer_fields_everywhere(self):
        data = EnemDevAdapter().sanitize("", {"questions": [api_item(1)], "x": [{"isCorrect": 1}]})
        text = json.dumps(data)
        for k in ("correctAlternative", "isCorrect", "gabarito"):
            self.assertNotIn(k, text)

    def test_normalize_basic(self):
        q = EnemDevAdapter().normalize(api_item(136, context="**Título**\n\nCorpo"))
        self.assertEqual(q.id, "enem-2022-136")
        self.assertEqual((q.source, q.edition, q.number), ("enem", 2022, 136))
        self.assertEqual(q.area, "mathematics")
        self.assertEqual(q.subject, "Matemática")
        self.assertEqual(q.statement, "Título\n\nCorpo\n\nQual?")
        self.assertEqual(q.alternatives, [f"alt {c}" for c in "ABCDE"])
        self.assertEqual(q.exclusions, [])
        self.assertFalse(hasattr(q, "correct_alternative"))

    def test_foreign_language_id_and_subject(self):
        q = EnemDevAdapter().normalize(api_item(1, discipline="linguagens", language="espanhol"))
        self.assertEqual(q.id, "enem-2022-1-espanhol")
        self.assertEqual(q.subject, "Espanhol")
        q = EnemDevAdapter().normalize(api_item(1, discipline="linguagens", language="ingles"))
        self.assertEqual(q.id, "enem-2022-1-ingles")
        self.assertEqual(q.subject, "Inglês")

    def test_subject_left_for_classifier(self):
        q = EnemDevAdapter().normalize(api_item(50, discipline="ciencias-humanas"))
        self.assertIsNone(q.subject)
        self.assertEqual(q.area, "humanities")

    def test_image_exclusions(self):
        a = EnemDevAdapter()
        self.assertIn("imagem_no_contexto", a.normalize(api_item(1, context="![](http://x/a.png)")).exclusions)
        self.assertIn("imagem_em_files", a.normalize(api_item(1, files=["http://x/a.png"])).exclusions)
        item = api_item(1)
        item["alternatives"][2]["file"] = "http://x/b.png"
        self.assertIn("imagem_em_alternativa", a.normalize(item).exclusions)

    def test_lost_exponent_is_excluded(self):
        a = EnemDevAdapter()
        item = api_item(1, alts=["1,1x10​−1​", "b", "c", "d", "e"])
        self.assertIn("expoente_perdido_na_fonte", a.normalize(item).exclusions)
        item = api_item(1, context="curta​duração")
        self.assertNotIn("expoente_perdido_na_fonte", a.normalize(item).exclusions)

    def test_unknown_discipline_fails(self):
        with self.assertRaises(ValueError):
            EnemDevAdapter().normalize(api_item(1, discipline="outra"))

    def test_clean_markup_keeps_text_and_credits(self):
        self.assertEqual(clean_markup("**Título**"), "Título")
        self.assertEqual(clean_markup("um *termo* aqui"), "um termo aqui")
        self.assertEqual(clean_markup("2 * 3 e nota*"), "2 * 3 e nota*")
        self.assertEqual(clean_markup("x\n\nFULANO. Disponível em: site. Acesso em: 1 jan."),
                         "x\n\nFULANO. Disponível em: site. Acesso em: 1 jan.")

    def test_pagination_dedupe_and_one_by_one_recovery(self):
        items = [api_item(i) for i in range(1, 121)]
        items += [api_item(91, discipline="linguagens", language=lg) for lg in ("ingles", "espanhol")]
        qs, api = run_adapter({2022: items})
        ids = [q.id for q in qs]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(ids), 122)
        self.assertIn("enem-2022-91-ingles", ids)
        self.assertTrue(any("questions/91?language=" in c for c in api.calls))

    def test_inconsistent_language_is_excluded(self):
        items = [api_item(1), api_item(2, discipline="linguagens", language="espanhol")]
        api = FakeApi({2022: items})
        orig = api.get_json

        def wrong(url):
            data = orig(url)
            if "questions/2?language=espanhol" in url:
                data["language"] = None  # a API devolve outra língua
            return data

        qs = list(EnemDevAdapter().iter_questions(wrong, lambda m: None))
        bad = [q for q in qs if q.id == "enem-2022-2-espanhol"][0]
        self.assertIn("api_lingua_inconsistente", bad.exclusions)

    def test_years_limited_to_2009_2023(self):
        qs, _ = run_adapter({2008: [api_item(1, year=2008)], 2009: [api_item(1, year=2009)],
                             2024: [api_item(1, year=2024)]})
        self.assertEqual([q.edition for q in qs], [2009])


class ExclusionTest(unittest.TestCase):
    def raw(self, **kw):
        base = dict(source="enem", edition=2022, number=1, id="enem-2022-1", area="mathematics",
                    statement="Enunciado", alternatives=list("abcde"))
        base.update(kw)
        return RawQuestion(**base)

    def test_ok(self):
        self.assertEqual(ba.exclusion_reasons(self.raw(), None), [])

    def test_alternative_count(self):
        self.assertEqual(ba.exclusion_reasons(self.raw(alternatives=list("abcd")), None),
                         ["alternativas_diferente_de_5"])

    def test_empty_alternative(self):
        self.assertIn("alternativa_vazia", ba.exclusion_reasons(self.raw(alternatives=["a", "", "c", "d", "e"]), None))

    def test_latex_superscript_brace(self):
        self.assertIn("formula_latex", ba.exclusion_reasons(self.raw(statement="10^{3} litros"), None))

    def test_latex(self):
        for t in (r"calcule \frac{1}{2}", r"valor $x^2 + 1$ final", r"\(a\)", "$$x$$"):
            self.assertIn("formula_latex", ba.exclusion_reasons(self.raw(statement=t), None), t)

    def test_money_is_not_latex(self):
        t = "Custa R$ 10 e depois US$ 20, ou $ 5 mais $ 6."
        self.assertNotIn("formula_latex", ba.exclusion_reasons(self.raw(statement=t), None))

    def test_glyph(self):
        covered = {ord(c) for c in "Enunciadoabcde \n"}
        self.assertEqual(ba.exclusion_reasons(self.raw(), covered), [])
        self.assertIn("glifo_ausente_na_inter", ba.exclusion_reasons(self.raw(statement="Enun ☃"), covered))

    def test_adapter_reasons_kept_first(self):
        r = ba.exclusion_reasons(self.raw(exclusions=["imagem_no_contexto"], alternatives=list("abcd")), None)
        self.assertEqual(r[0], "imagem_no_contexto")


class GlyphTest(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(FONT), "fonte Inter ausente")
    def test_inter_cmap(self):
        cov = covered_codepoints(FONT)
        self.assertEqual(missing_chars("Função: ação, é ü ç ~ º “OK”\n", cov), [])
        self.assertIn("☃", missing_chars("☃", cov))


class CleanMarkupTest(unittest.TestCase):
    COV = {ord(c) for c in "•₂²"}

    def test_underscore_italic_between_delimiters(self):
        self.assertEqual(clean_markup("T. _Grécia. A vida_ cotidiana"), "T. Grécia. A vida cotidiana")
        self.assertEqual(clean_markup("são _Coffea canephora_ e _Coffea arabica_."),
                         "são Coffea canephora e Coffea arabica.")
        self.assertEqual(clean_markup("(_texto_)"), "(texto)")

    def test_underscore_inside_words_and_urls_survives(self):
        for t in ("utimas_noticias.php", "http://x.com/a_b/c_d.html", "snake_case_name",
                  "1 3 _ 9 8", "um _ solto", "__init__"):
            self.assertEqual(clean_markup(t), t)

    def test_escaped_chars(self):
        self.assertEqual(clean_markup(r"a\_b \* \[x\] y\=z"), "a_b * [x] y=z")
        self.assertEqual(clean_markup(r"\_nao italico\_"), "_nao italico_")

    def test_links_become_text(self):
        self.assertEqual(clean_markup("veja [o site](https://a.b/c_d) agora"), "veja o site agora")

    def test_list_items(self):
        t = "Intro\n*   item um\n*   item dois"
        self.assertEqual(clean_markup(t, self.COV), "Intro\n• item um\n• item dois")
        self.assertEqual(clean_markup(t, set()), "Intro\n- item um\n- item dois")
        self.assertEqual(clean_markup("* nota de rodapé"), "* nota de rodapé")

    def test_bold_and_broken_bold(self):
        self.assertEqual(clean_markup("N.\xa0**O Renascimento**, x"), "N. O Renascimento, x")
        self.assertEqual(clean_markup("a penúria**, mas a abundância"), "a penúria, mas a abundância")
        self.assertEqual(clean_markup(r"a penúria\*\*, mas a abundância"), "a penúria, mas a abundância")

    def test_html(self):
        self.assertEqual(clean_markup("CO<sub>2</sub> e m<sup>2</sup>", self.COV), "CO₂ e m²")
        self.assertEqual(clean_markup("CO<sub>2</sub>", set()), "CO2")
        self.assertEqual(clean_markup("<p style='x'><strong>a</strong> &iacute;</p>"), "a í")

    def test_zero_width_removed(self):
        self.assertEqual(clean_markup("a​b‌‍⁠﻿c"), "abc")

    def test_headers(self):
        self.assertEqual(clean_markup("##### TIPO DE CURVA\ntexto"), "TIPO DE CURVA\ntexto")

    def test_nfc_and_spaces(self):
        self.assertEqual(clean_markup("é x"), "é x")
        self.assertEqual(clean_markup("a\xa0b  c \nd\t\ne"), "a b c\nd\ne")


class RedirectTest(unittest.TestCase):
    def test_redirect_outside_prefix_refused(self):
        from fetcher import _PrefixRedirect
        h = _PrefixRedirect(["https://api.test/"])
        with self.assertRaises(FetchError):
            h.redirect_request(None, None, 302, "x", {}, "https://evil.example/x")


class SourcesRegistryTest(unittest.TestCase):
    def write(self, sources):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "s.json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"sources": sources}, f)
        return p

    def good(self, **kw):
        s = {
            "id": "enem", "name": "n", "via": "v", "officialUrl": "https://a.gov.br/x",
            "license": "l", "licenseUrl": "https://b.org/l", "licenseEvidence": "e",
            "attribution": "a", "notice": "n", "authorized": True,
        }
        s.update(kw)
        return s

    def test_real_registry_loads(self):
        srcs = ba.load_sources(os.path.join(ACERVO, "sources.json"))
        self.assertEqual([s["id"] for s in srcs], ["enem"])
        for s in srcs:
            self.assertTrue(s["officialUrl"].startswith("https://"))
            self.assertTrue(s["licenseEvidence"].strip())
            self.assertIs(s["authorized"], True)

    def test_refuses_unauthorized(self):
        for bad in ({"authorized": False}, {"authorized": "true"}):
            with self.assertRaises(ba.SourceRefused):
                ba.load_sources(self.write([self.good(**bad)]))
        s = self.good()
        del s["authorized"]
        with self.assertRaises(ba.SourceRefused):
            ba.load_sources(self.write([s]))

    def test_refuses_missing_evidence_or_link(self):
        with self.assertRaises(ba.SourceRefused):
            ba.load_sources(self.write([self.good(licenseEvidence=" ")]))
        with self.assertRaises(ba.SourceRefused):
            ba.load_sources(self.write([self.good(officialUrl="")]))

    def test_refuses_source_without_adapter(self):
        with self.assertRaises(ba.SourceRefused):
            ba.load_sources(self.write([self.good(id="outra")]))

    def test_main_exits_with_error_when_refused(self):
        p = self.write([self.good(authorized=False)])
        err = io.StringIO()
        old, sys.stderr = sys.stderr, err
        try:
            code = ba.main(["--sources", p, "--cache-dir", tempfile.mkdtemp(),
                            "--out", os.path.join(tempfile.mkdtemp(), "o.json")])
        finally:
            sys.stderr = old
        self.assertEqual(code, 2)
        self.assertIn("authorized", err.getvalue())

    def test_second_source_needs_no_script_change(self):
        class Other(SourceAdapter):
            id = "outra"
            allowed_prefix = "https://example.org/"

            def iter_questions(self, get_json, log):
                yield RawQuestion("outra", 2020, 7, "outra-2020-7", "humanities", "Enunciado",
                                  list("abcde"))

        ADAPTERS["outra"] = Other
        try:
            srcs = ba.load_sources(self.write([self.good(), self.good(id="outra")]))
            fake = FakeApi({2022: [api_item(1)]})

            def factory(adapter):
                class F:
                    get_json = staticmethod(fake.get_json)
                return F

            asset, kept, _ = ba.build(srcs, factory, None, "2026-01-01", log=lambda m: None)
            self.assertEqual({q["source"] for q in asset["questions"]}, {"enem", "outra"})
            self.assertEqual({s["id"] for s in asset["sources"]}, {"enem", "outra"})
        finally:
            del ADAPTERS["outra"]


class FetcherTest(unittest.TestCase):
    class Clock:
        def __init__(self):
            self.t = 0.0
            self.sleeps = []

        def now(self):
            return self.t

        def sleep(self, s):
            self.sleeps.append(s)
            self.t += s

    class Resp:
        def __init__(self, body):
            self.body = body

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self, n=-1):
            return self.body

    def make(self, script, **kw):
        clock = self.Clock()
        calls = []

        def opener(req):
            calls.append((clock.t, req))
            r = script.pop(0)
            if isinstance(r, Exception):
                raise r
            return self.Resp(json.dumps(r).encode())

        f = Fetcher(tempfile.mkdtemp(), ["https://api.test/"], opener=opener,
                    sleep=clock.sleep, clock=clock.now, **kw)
        return f, clock, calls

    def http_error(self, code, retry_after=None):
        h = {"Retry-After": retry_after} if retry_after else {}
        import email.message
        m = email.message.Message()
        for k, v in h.items():
            m[k] = v
        return urllib.error.HTTPError("https://api.test/x", code, "x", m, None)

    def test_one_request_per_second(self):
        f, clock, calls = self.make([{"a": 1}, {"a": 2}, {"a": 3}])
        for i in range(3):
            f.get_json(f"https://api.test/{i}")
        times = [t for t, _ in calls]
        self.assertTrue(all(b - a >= 1.0 for a, b in zip(times, times[1:])), times)

    def test_user_agent_is_generic(self):
        f, _, calls = self.make([{"a": 1}])
        f.get_json("https://api.test/x")
        ua = calls[0][1].get_header("User-agent")
        self.assertEqual(ua, "IaGo-acervo/1.0")
        self.assertNotIn("@", ua)

    def test_429_waits_retry_after_then_succeeds(self):
        f, clock, calls = self.make([self.http_error(429, "7"), {"ok": True}])
        self.assertEqual(f.get_json("https://api.test/x"), {"ok": True})
        self.assertIn(7.0, clock.sleeps)
        self.assertEqual(len(calls), 2)

    def test_429_without_header_backs_off_and_eventually_fails(self):
        f, clock, _ = self.make([self.http_error(429) for _ in range(3)], max_attempts=3)
        with self.assertRaises(FetchError):
            f.get_json("https://api.test/x")
        self.assertTrue(clock.sleeps)

    def test_429_wait_is_capped(self):
        f, clock, _ = self.make([self.http_error(429, "99999"), {"ok": 1}], max_wait=30)
        f.get_json("https://api.test/x")
        self.assertLessEqual(max(clock.sleeps), 30)

    def test_server_error_retries_but_404_does_not(self):
        f, _, calls = self.make([self.http_error(503), {"ok": 1}])
        self.assertEqual(f.get_json("https://api.test/x"), {"ok": 1})
        f, _, calls = self.make([self.http_error(404)])
        with self.assertRaises(FetchError):
            f.get_json("https://api.test/y")
        self.assertEqual(len(calls), 1)

    def test_cache_avoids_network_and_sanitizes_before_writing(self):
        f, _, calls = self.make([{"correctAlternative": "A", "v": 1}])
        f.sanitize = lambda url, d: {k: v for k, v in d.items() if k != "correctAlternative"}
        self.assertEqual(f.get_json("https://api.test/x"), {"v": 1})
        self.assertEqual(f.get_json("https://api.test/x"), {"v": 1})
        self.assertEqual(len(calls), 1)
        for name in os.listdir(f.cache_dir):
            with open(os.path.join(f.cache_dir, name), encoding="utf-8") as fh:
                self.assertNotIn("correctAlternative", fh.read())

    def test_rejects_foreign_url_and_offline_miss(self):
        f, _, calls = self.make([])
        with self.assertRaises(FetchError):
            f.get_json("https://evil.example/x")
        f.offline = True
        with self.assertRaises(FetchError):
            f.get_json("https://api.test/never")
        self.assertEqual(calls, [])


class BuildTest(unittest.TestCase):
    def items(self):
        its = [api_item(i) for i in range(1, 8)]
        its.append(api_item(8, context="![](http://x/a.png)"))
        its.append(api_item(9, alts=["a", "b", "c", "d"]))
        its.append(api_item(10, discipline="ciencias-humanas"))
        its += [api_item(91, discipline="linguagens", language="ingles")]
        return its

    def build_once(self, order=1):
        fake = FakeApi({2022: self.items()[::order]})

        def factory(adapter):
            class F:
                get_json = staticmethod(fake.get_json)
            return F

        srcs = ba.load_sources(os.path.join(ACERVO, "sources.json"))
        return ba.build(srcs, factory, None, "2026-11-07", log=lambda m: None)

    def test_asset_shape_and_stable_output(self):
        asset, kept, excluded = self.build_once()
        self.assertEqual(asset["schemaVersion"], 1)
        self.assertEqual(asset["sources"][0]["id"], "enem")
        for k in ("attribution", "officialUrl"):
            self.assertTrue(asset["sources"][0][k])
        for q in asset["questions"]:
            self.assertTrue(q["id"].startswith(q["source"] + "-"))
            self.assertEqual(len(q["alternatives"]), 5)
            self.assertNotIn("media", q)
        self.assertEqual(len(excluded), 2)
        self.assertEqual(sorted(e[1][0] for e in excluded),
                         ["alternativas_diferente_de_5", "imagem_no_contexto"])
        again, _, _ = self.build_once(order=-1)  # mesma entrada em outra ordem
        self.assertEqual(ba.dump_asset(asset), ba.dump_asset(again))

    def test_license_fields_are_not_in_asset(self):
        asset, _, _ = self.build_once()
        for s in asset["sources"]:
            for k in ("license", "licenseUrl", "licenseEvidence", "authorized"):
                self.assertNotIn(k, s)

    def test_no_answer_fields_in_generated_asset(self):  # CA-F5
        asset, _, _ = self.build_once()
        text = ba.dump_asset(asset)
        self.assertEqual(ba.forbidden_keys(asset), set())
        self.assertFalse(ba.has_forbidden_word(text))
        for k in ("correctAlternative", "isCorrect"):
            self.assertNotIn(k, text)
        self.assertIsInstance(json.loads(text), dict)

    def test_report_counts(self):
        _, kept, excluded = self.build_once()
        rep = ba.report_text(kept, excluded)
        self.assertIn("2022: 9 / 11", rep)
        self.assertIn("imagem_no_contexto: 1", rep)
        self.assertIn("alternativas_diferente_de_5: 1", rep)
        self.assertIn("Matemática", rep)

    def test_duplicate_ids_fail(self):
        class Dup(SourceAdapter):
            id = "enem"

            def iter_questions(self, get_json, log):
                for _ in range(2):
                    yield RawQuestion("enem", 2020, 1, "enem-2020-1", "mathematics", "E", list("abcde"))

        old = ADAPTERS["enem"]
        ADAPTERS["enem"] = Dup
        try:
            srcs = ba.load_sources(os.path.join(ACERVO, "sources.json"))

            class F:
                get_json = staticmethod(lambda u: None)

            with self.assertRaises(ValueError):
                ba.build(srcs, lambda a: F, None, "2026-01-01", log=lambda m: None)
        finally:
            ADAPTERS["enem"] = old


class RepoRulesTest(unittest.TestCase):
    def test_no_commercial_sources_mentioned(self):  # CA-F4
        banned = ["qconcursos", "tec" + "concursos", "tec " + "concursos", "estuda" + ".com"]
        for root, _, files in os.walk(ACERVO):
            for name in files:
                if name.endswith((".py", ".json", ".md", ".txt")) and name != "test_acervo.py":
                    with open(os.path.join(root, name), encoding="utf-8") as f:
                        text = f.read().lower()
                    for b in banned:
                        self.assertNotIn(b, text, f"{name}: {b}")

    def test_word_check_ignores_urls_only(self):
        self.assertFalse(ba.has_forbidden_word('x https://a.gov.br/provas-e-gabaritos y'))
        self.assertTrue(ba.has_forbidden_word("Sem gabarito."))

    def test_only_enem_dev_host_in_adapter(self):
        self.assertEqual(EnemDevAdapter.allowed_prefix, "https://api.enem.dev/v1/")

    @unittest.skipUnless(os.path.exists(ASSET), "asset ainda não gerado")
    def test_generated_asset(self):  # CA-F5 e partes do CA-B2
        with open(ASSET, encoding="utf-8") as f:
            raw = f.read()
        data = json.loads(raw)
        self.assertEqual(data["schemaVersion"], 1)
        self.assertEqual(ba.forbidden_keys(data), set())
        self.assertFalse(ba.has_forbidden_word(raw))
        for k in ("correctAlternative", "isCorrect"):
            self.assertNotIn(k, raw)
        self.assertNotIn("sem alteração", raw.lower())
        src = data["sources"][0]
        self.assertEqual(src["attribution"], "Provas do ENEM, INEP.")
        self.assertEqual(
            src["notice"],
            "Texto das provas do INEP, reproduzido para uso educacional. Formatação ajustada. "
            "Confira o original em " + src["officialUrl"])
        self.assertNotIn("license", src)
        self.assertNotIn("licenseUrl", src)
        src_ids = {s["id"] for s in data["sources"]}
        qs = data["questions"]
        self.assertGreaterEqual(len(qs), 1000)
        self.assertEqual(len({q["id"] for q in qs}), len(qs))
        self.assertEqual({q["area"] for q in qs},
                         {"languages", "humanities", "naturalSciences", "mathematics"})
        cov = covered_codepoints(FONT) if os.path.exists(FONT) else None
        for q in qs:
            self.assertIn(q["source"], src_ids)
            self.assertTrue(q["id"].startswith(q["source"] + "-"))
            self.assertEqual(len(q["alternatives"]), 5)
            self.assertNotIn("media", q)
            if cov:
                self.assertEqual(missing_chars(q["statement"] + "".join(q["alternatives"]), cov), [], q["id"])


if __name__ == "__main__":
    unittest.main()
