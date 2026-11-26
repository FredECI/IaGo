"""Testes do formato v2, da taxonomia e da classificação (BM1, BM2, BM5). Sem rede."""

import csv
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ACERVO = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(ACERVO))
sys.path.insert(0, ACERVO)

import acervo_v2 as v2  # noqa: E402
import build_acervo as ba  # noqa: E402
import classify  # noqa: E402
from sources.base import RawQuestion  # noqa: E402

TAXONOMY = os.path.join(ACERVO, "taxonomy.json")
V2_DIR = os.path.join(REPO, "assets", "acervo", "v2")
SOURCES = [{
    "id": "enem", "kind": "questions", "name": "ENEM (INEP)", "via": "api.enem.dev",
    "officialUrl": "https://a.gov.br/x", "attribution": "Provas.", "notice": "Aviso.",
}]


def rq(i, area="humanities", subject=None, source="enem", edition=2022):
    return RawQuestion(
        source=source, edition=edition, number=i, id=f"{source}-{edition}-{i}",
        area=area, statement=f"Enunciado {i}", alternatives=[f"alt {c}" for c in "ABCDE"],
        subject=subject,
    )


def write_jsonl(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


class TaxonomyTest(unittest.TestCase):  # BM1
    def test_real_taxonomy_loads_and_follows_the_rules(self):
        t = v2.load_taxonomy(TAXONOMY)
        self.assertEqual(t["taxonomyVersion"], 1)
        for subject, topics in t["subjects"].items():
            self.assertLessEqual(len(topics), 14, subject)
            self.assertNotIn("Outros", topics, subject)
            if subject != "Redação":
                self.assertGreaterEqual(len(topics), 3, subject)
        self.assertEqual(t["subjects"]["Redação"], [])
        self.assertEqual(sum(len(v) for v in t["areas"].values()), 15)
        for hint in t["skillHints"]:
            for topic in hint["topics"]:
                self.assertIn(topic, t["subjects"]["Matemática"])

    def test_dart_catalog_matches_taxonomy_areas(self):
        with open(os.path.join(REPO, "lib", "domain", "area.dart"), encoding="utf-8") as f:
            dart = f.read()
        t = v2.load_taxonomy(TAXONOMY)
        for subject in (s for subs in t["areas"].values() for s in subs):
            self.assertIn(f"'{subject}'", dart)

    def test_rejects_subject_without_area(self):
        t = json.load(open(TAXONOMY, encoding="utf-8"))
        t["subjects"]["Nova"] = ["A"]
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "t.json")
            json.dump(t, open(p, "w", encoding="utf-8"))
            with self.assertRaises(v2.BuildError):
                v2.load_taxonomy(p)


class BuildV2Test(unittest.TestCase):  # BM5 e CA-BM4
    def setUp(self):
        self.tax = v2.load_taxonomy(TAXONOMY)

    def build(self, kept, cls=None, **kw):
        return ba.build_v2(SOURCES, kept, self.tax, cls or {}, "2026-11-26", **kw)

    def test_fails_without_subject_and_passes_with_flag(self):
        kept = [rq(1), rq(2, "mathematics", "Matemática")]
        with self.assertRaises(v2.BuildError):
            self.build(kept)
        files, qs = self.build(kept, allow_unclassified=True)
        self.assertEqual(sum("subject" in d for d in qs), 1)
        self.assertEqual(sorted(files), [
            "humanities.json", "index.json", "languages.json",
            "mathematics.json", "naturalSciences.json",
        ])

    def test_classification_fills_subject_topic_and_by(self):
        cls = {"enem-2022-1": {"id": "enem-2022-1", "subject": "História",
                               "topic": "Era Vargas", "by": "agent"}}
        _, qs = self.build([rq(1)], cls)
        self.assertEqual((qs[0]["subject"], qs[0]["topic"], qs[0]["classifiedBy"]),
                         ("História", "Era Vargas", "agent"))

    def test_precedence_human_over_source_over_agent(self):
        q = rq(1, "mathematics", "Matemática")
        agent = {"id": q.id, "subject": "Matemática", "topic": "Funções", "by": "agent"}
        _, qs = self.build([q], {q.id: agent})
        self.assertEqual((qs[0]["classifiedBy"], qs[0]["topic"]), ("source", "Funções"))
        human = {"id": q.id, "subject": "Matemática", "topic": "Estatística", "by": "human"}
        _, qs = self.build([q], {q.id: human})
        self.assertEqual((qs[0]["classifiedBy"], qs[0]["topic"]), ("human", "Estatística"))

    def test_read_classification_keeps_highest_precedence(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_jsonl(os.path.join(tmp, "a.jsonl"),
                        [{"id": "x", "subject": "História", "by": "agent"}])
            write_jsonl(os.path.join(tmp, "b.jsonl"),
                        [{"id": "x", "subject": "Geografia", "by": "human"}])
            write_jsonl(os.path.join(tmp, "sub", "c.jsonl"),
                        [{"id": "y", "subject": "Geografia"}])  # subpasta é ignorada
            got = v2.read_classification(tmp)
        self.assertEqual(list(got), ["x"])
        self.assertEqual(got["x"]["subject"], "Geografia")

    def test_unknown_classification_id_fails(self):
        cls = {"enem-2022-999": {"id": "enem-2022-999", "subject": "História", "by": "agent"}}
        with self.assertRaises(v2.BuildError):
            self.build([rq(1, "humanities", "História")], cls)

    def test_subject_outside_area_catalog_fails(self):
        cls = {"enem-2022-1": {"id": "enem-2022-1", "subject": "Física", "by": "agent"}}
        with self.assertRaises(v2.BuildError):
            self.build([rq(1)], cls)

    def test_topic_outside_taxonomy_fails(self):
        cls = {"enem-2022-1": {"id": "enem-2022-1", "subject": "História",
                               "topic": "Inventado", "by": "agent"}}
        with self.assertRaises(v2.BuildError):
            self.build([rq(1)], cls)

    def test_published_id_missing_fails_unless_removed(self):
        kept = [rq(1, "mathematics", "Matemática")]
        with self.assertRaises(v2.BuildError):
            self.build(kept, ids_v1=["enem-2022-1", "enem-2022-2"])
        self.build(kept, ids_v1=["enem-2022-1", "enem-2022-2"],
                   removed={"enem-2022-2": {"id": "enem-2022-2"}})

    def test_removed_json_needs_reason_and_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "removed.json")
            with open(p, "w", encoding="utf-8") as f:
                json.dump({"removed": [{"id": "a", "reason": "capricho", "date": "2026-11-26"}]}, f)
            with self.assertRaises(v2.BuildError):
                v2.load_removed(p)

    def test_shard_size_limit(self):
        with self.assertRaises(v2.BuildError):
            v2.check_sizes({"index.json": "{}", "languages.json": "x" * (v2.MAX_SHARD_BYTES + 1)})
        with self.assertRaises(v2.BuildError):
            v2.check_sizes({f"{i}.json": "x" * (v2.MAX_SHARD_BYTES - 1) for i in range(5)})

    def test_index_counts_taxonomy_and_shards(self):
        kept = [rq(1, "mathematics", "Matemática"), rq(2, "mathematics", "Matemática"),
                rq(3, "naturalSciences")]
        cls = {"enem-2022-3": {"id": "enem-2022-3", "subject": "Física", "by": "agent"}}
        files, _ = self.build(kept, cls)
        index = json.loads(files["index.json"])
        self.assertEqual(index["schemaVersion"], 2)
        self.assertEqual(index["taxonomy"]["Física"], self.tax["subjects"]["Física"])
        self.assertEqual(index["sources"][0]["kind"], "questions")
        self.assertEqual({(c["subject"], c["count"]) for c in index["counts"]},
                         {("Matemática", 2), ("Física", 1)})
        self.assertEqual([s["area"] for s in index["shards"]], list(v2.AREA_ORDER))
        self.assertEqual({s["area"]: s["count"] for s in index["shards"]}["mathematics"], 2)
        self.assertTrue(all(s["path"] == f"assets/acervo/v2/{s['area']}.json"
                            for s in index["shards"]))

    def test_output_is_stable_and_has_no_answer_keys(self):
        kept = [rq(2, "mathematics", "Matemática"), rq(1, "mathematics", "Matemática")]
        a, _ = self.build(kept)
        b, _ = self.build(kept)
        self.assertEqual(a, b)
        for text in a.values():
            self.assertEqual(ba.forbidden_keys(json.loads(text)), set())

    def test_answer_keys_are_detected(self):  # CA-BM5
        self.assertEqual(
            ba.forbidden_keys({"a": [{"TX_GABARITO": 1}, {"answer": "B"}, {"isCorrect": True}]}),
            {"TX_GABARITO", "answer", "isCorrect"},
        )

    def test_metadata_source_brings_no_question(self):
        srcs = [dict(SOURCES[0], license="l", licenseUrl="https://b.org/l",
                     licenseEvidence="e", authorized=True),
                dict(SOURCES[0], id="inepdados", kind="metadata", license="l",
                     licenseUrl="https://b.org/l", licenseEvidence="e", authorized=True)]
        calls = []

        class Adapter:
            allowed_prefix = "https://x/"

            def __init__(self, covered=None):
                pass

            def sanitize(self, url, data):
                return data

            def iter_questions(self, get_json, log):
                calls.append(1)
                return iter([rq(1, "mathematics", "Matemática")])

        saved = dict(ba.ADAPTERS)
        ba.ADAPTERS.update({"enem": Adapter, "inepdados": Adapter})
        try:
            class F:
                get_json = staticmethod(lambda u: None)
            _, kept, _ = ba.build(srcs, lambda a: F, None, "2026-11-26", log=lambda m: None)
        finally:
            ba.ADAPTERS.clear()
            ba.ADAPTERS.update(saved)
        self.assertEqual(len(kept), 1)
        self.assertEqual(len(calls), 1)

    def test_registry_defaults_and_validates_kind(self):
        self.assertEqual(ba.source_adapters({"id": "enem"}), ["enem"])
        self.assertEqual(ba.source_adapters({"id": "enem", "adapters": ["a", "b"]}), ["a", "b"])
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "s.json")
            src = dict(SOURCES[0], license="l", licenseUrl="https://b.org/l",
                       licenseEvidence="e", authorized=True, kind="outra")
            json.dump({"sources": [src]}, open(p, "w", encoding="utf-8"))
            with self.assertRaises(ba.SourceRefused):
                ba.load_sources(p)


@unittest.skipUnless(os.path.exists(os.path.join(V2_DIR, "index.json")), "v2 ainda não gerado")
class GeneratedV2Test(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(V2_DIR, "index.json"), encoding="utf-8") as f:
            self.index = json.load(f)
        self.tax = v2.load_taxonomy(TAXONOMY)
        self.questions = []
        for s in self.index["shards"]:
            with open(os.path.join(REPO, s["path"]), encoding="utf-8") as f:
                part = json.load(f)
            self.assertEqual(part["area"], s["area"])
            self.assertEqual(len(part["questions"]), s["count"])
            self.questions += part["questions"]

    def test_ids_v1_all_present_or_removed(self):  # CA-BM3
        ids = {q["id"] for q in self.questions}
        removed = v2.load_removed(os.path.join(ACERVO, "removed.json"))
        v1 = v2.load_ids_v1(os.path.join(ACERVO, "ids-v1.txt"))
        self.assertEqual(len(v1), 1687)
        self.assertEqual([i for i in v1 if i not in ids and i not in removed], [])

    def test_sizes_within_limits(self):
        total = 0
        for name in os.listdir(V2_DIR):
            size = os.path.getsize(os.path.join(V2_DIR, name))
            total += size
            if name != "index.json":
                self.assertLessEqual(size, v2.MAX_SHARD_BYTES, name)
        self.assertLessEqual(total, v2.MAX_TOTAL_BYTES)

    def test_every_value_is_valid_and_has_no_answers(self):  # CA-BM1 e CA-BM5
        counted = 0
        for q in self.questions:
            self.assertTrue(q["id"].startswith(q["source"] + "-"))
            if "subject" in q:
                counted += 1
                self.assertIn(q["subject"], self.tax["areas"][q["area"]], q["id"])
                self.assertIn(q["classifiedBy"], v2.BY_RANK)
                if "topic" in q:
                    self.assertIn(q["topic"], self.tax["subjects"][q["subject"]], q["id"])
            self.assertEqual(len(q["alternatives"]), 5)
        self.assertEqual(ba.forbidden_keys(self.index), set())
        # counts somam as questões que têm matéria
        self.assertEqual(sum(c["count"] for c in self.index["counts"]), counted)

    def test_full_coverage_once_classified(self):  # CA-BM1
        unclassified = [q["id"] for q in self.questions if "subject" not in q]
        if unclassified:
            self.skipTest(f"{len(unclassified)} questões ainda sem classificação")
        topics = sum("topic" in q for q in self.questions)
        self.assertGreaterEqual(topics / len(self.questions), 0.85)


class ClassifyTest(unittest.TestCase):  # BM2
    def setUp(self):
        self.tax = v2.load_taxonomy(TAXONOMY)
        self.batch = [
            {"id": "a", "area": "humanities"},
            {"id": "b", "area": "languages", "subject": "Inglês"},
            {"id": "c", "area": "naturalSciences"},
        ]

    def run_merge(self, answers):
        return classify.merge(self.batch, [(f"t:{i}", r) for i, r in enumerate(answers)], self.tax)

    def test_valid_answers_are_merged_in_batch_order(self):
        entries, problems, warnings = self.run_merge([
            {"id": "c", "subject": "Física", "topic": "Óptica", "confidence": "high"},
            {"id": "a", "subject": "História", "topic": "", "confidence": "medium"},
            {"id": "b", "subject": "Inglês", "topic": "Vocabulário em contexto", "confidence": "low"},
        ])
        self.assertEqual((problems, warnings), ([], []))
        self.assertEqual([e["id"] for e in entries], ["a", "b", "c"])
        self.assertTrue(all(e["by"] == "agent" and e["reviewed"] is False for e in entries))

    def test_subject_outside_area_is_discarded(self):
        entries, problems, _ = self.run_merge([
            {"id": "a", "subject": "Física", "confidence": "high"},
        ])
        self.assertEqual(entries, [])
        self.assertTrue(any("fora do catálogo" in p for p in problems))

    def test_unknown_id_and_missing_answers_are_problems(self):
        _, problems, _ = self.run_merge([
            {"id": "zzz", "subject": "História", "confidence": "high"},
        ])
        self.assertTrue(any("id desconhecido" in p for p in problems))
        self.assertEqual(sum(p.startswith("sem resposta") for p in problems), 3)

    def test_invalid_topic_becomes_empty_with_warning(self):
        entries, problems, warnings = self.run_merge([
            {"id": "a", "subject": "História", "topic": "Inventado", "confidence": "high"},
        ])
        self.assertEqual(entries[0]["topic"], "")
        self.assertEqual(len(warnings), 1)
        self.assertFalse(any("Inventado" in p for p in problems))

    def test_source_subject_prevails(self):
        entries, _, warnings = self.run_merge([
            {"id": "b", "subject": "Português", "topic": "Interpretação de texto",
             "confidence": "high"},
        ])
        self.assertEqual(entries[0]["subject"], "Inglês")
        self.assertTrue(any("a fonte garante" in w for w in warnings))

    def test_bad_confidence_becomes_low_and_json_error_is_a_problem(self):
        entries, problems, warnings = self.run_merge([
            {"id": "a", "subject": "História", "confidence": "certeza"},
            {"_error": "JSON inválido (x)"},
        ])
        self.assertEqual(entries[0]["confidence"], "low")
        self.assertEqual(len(warnings), 1)
        self.assertTrue(any("JSON inválido" in p for p in problems))

    def test_trim_keeps_start_and_end(self):
        text = "inicio " + "x" * 1000 + " fim"
        out = classify.trim_statement(text, 350)
        self.assertLessEqual(len(out), 360)
        self.assertTrue(out.startswith("inicio"))
        self.assertTrue(out.endswith("fim"))
        self.assertIn("[...]", out)
        self.assertEqual(classify.trim_statement("curto  texto", 350), "curto texto")

    def test_split_even(self):
        parts = classify.split_even(list(range(10)), 4)
        self.assertEqual([len(p) for p in parts], [3, 3, 2, 2])
        self.assertEqual([x for p in parts for x in p], list(range(10)))

    def test_cli_batches_merge_sample_and_build_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            shards = os.path.join(tmp, "v2")
            os.makedirs(shards)
            ids = {}
            for area in v2.AREA_ORDER:
                qs = []
                for n in range(1, 9):
                    d = {"id": f"enem-2022-{area[:2]}{n}", "source": "enem", "year": 2022,
                         "number": n, "area": area, "statement": "E " * 400,
                         "alternatives": ["a" * 100] * 5}
                    qs.append(d)
                    ids[d["id"]] = area
                with open(os.path.join(shards, f"{area}.json"), "w", encoding="utf-8") as f:
                    f.write(v2.dump_shard(area, qs))
            batches = os.path.join(tmp, "batches")
            self.assertEqual(classify.main(["batches", "--shards-dir", shards, "--out", batches,
                                            "--files", "4"]), 0)
            self.assertEqual(sorted(os.listdir(batches)),
                             [f"lote-{i}.jsonl" for i in range(1, 5)])
            first = json.loads(open(os.path.join(batches, "lote-1.jsonl"), encoding="utf-8")
                               .readline())
            self.assertLessEqual(len(first["statement"]), 360)
            self.assertLessEqual(len(first["alternatives"][0]), 40)

            out = os.path.join(tmp, "out")
            for n in range(1, 5):
                rows = [json.loads(ln) for ln in open(os.path.join(batches, f"lote-{n}.jsonl"),
                                                      encoding="utf-8")]
                first_subject = {a: self.tax["areas"][a][0] for a in v2.AREA_ORDER}
                write_jsonl(os.path.join(out, f"lote-{n}.jsonl"), [
                    {"id": r["id"], "subject": first_subject[r["area"]], "topic": "",
                     "confidence": "high" if i % 3 else "low"} for i, r in enumerate(rows)])
            merged = os.path.join(tmp, "enem.jsonl")
            self.assertEqual(classify.main(["merge", "--batches", batches, "--answers", out,
                                            "--output", merged]), 0)
            self.assertEqual(len(v2.read_classification(tmp)), 32)

            sample = os.path.join(tmp, "amostra.csv")
            self.assertEqual(classify.main(["sample", "--classification", merged,
                                            "--shards-dir", shards, "--out", sample,
                                            "--n", "8", "--seed", "1"]), 0)
            with open(sample, encoding="utf-8-sig", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 8)
            for area in v2.AREA_ORDER:
                self.assertEqual(sum(r["area"] == area for r in rows), 2)

            # Sem uma das respostas, o merge acusa e termina com código 1.
            os.remove(os.path.join(out, "lote-4.jsonl"))
            self.assertEqual(classify.main(["merge", "--batches", batches, "--answers", out,
                                            "--output", merged]), 1)
            self.assertEqual(classify.main(["merge", "--batches", batches, "--answers", out,
                                            "--output", merged, "--allow-partial"]), 0)

    def test_sample_is_deterministic_and_stratified(self):
        entries = [{"id": f"{a}-{i}", "area": a, "confidence": ("low" if i % 4 == 0 else "high")}
                   for a in v2.AREA_ORDER for i in range(40)]
        one = classify.pick_sample(entries, 20, 2026)
        two = classify.pick_sample(entries, 20, 2026)
        self.assertEqual(one, two)
        for a in v2.AREA_ORDER:
            self.assertEqual(sum(e["area"] == a for e in one), 5)
        self.assertGreaterEqual(sum(e["confidence"] == "low" for e in one), 8)
        self.assertEqual(len({e["id"] for e in one}), 20)


if __name__ == "__main__":
    unittest.main()
