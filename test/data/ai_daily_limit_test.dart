import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/ai_daily_limit.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiDailyLimiter limiter(
  AiUsageStore store,
  DateTime Function() now, {
  String owner = 'u1',
  int limit = 2,
}) => AiDailyLimiter(store: store, owner: owner, limit: limit, now: now);

final file = ImportFile(
  name: 'a.png',
  mimeType: 'image/png',
  bytes: Uint8List(1),
);

Matcher dailyLimit() => throwsA(
  isA<AiException>().having((e) => e.failure, 'failure', AiFailure.dailyLimit),
);

void main() {
  test('consome até o limite e depois lança dailyLimit', () {
    final l = limiter(MemoryAiUsageStore(), () => DateTime(2026, 11, 10, 10));
    l.consume();
    l.consume();
    expect(l.hasRoom, isFalse);
    expect(l.consume, dailyLimit());
    expect(l.usedToday, 2);
  });

  test('o dia seguinte zera; usuários não se misturam', () {
    final store = MemoryAiUsageStore();
    var now = DateTime(2026, 11, 10, 23, 59);
    final a = limiter(store, () => now);
    final b = limiter(store, () => now, owner: 'u2');
    a.consume();
    a.consume();
    expect(a.hasRoom, isFalse);
    expect(b.hasRoom, isTrue);
    now = DateTime(2026, 11, 11, 0, 1);
    expect(a.hasRoom, isTrue);
    expect(a.usedToday, 0);
  });

  test('SharedPreferences: persiste e troca de dia', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 10, 8);
    limiter(PrefsAiUsageStore(prefs), () => now).consume();
    // Outra instância (reabriu o app) enxerga a contagem.
    final again = limiter(PrefsAiUsageStore(prefs), () => now);
    expect(again.usedToday, 1);
    again.consume();
    expect(again.hasRoom, isFalse);
    now = DateTime(2026, 11, 11, 8);
    expect(again.usedToday, 0);
    // Valor corrompido vale zero.
    await prefs.setString('ai_usage.u1', 'lixo');
    expect(again.usedToday, 0);
  });

  test('extrator: ao estourar, não chama o inner', () async {
    final inner = FakeQuestionExtractor();
    final l = limiter(
      MemoryAiUsageStore(),
      () => DateTime(2026, 11, 10),
      limit: 1,
    );
    final ex = DailyLimitedQuestionExtractor(inner, l);
    await ex.extract(file);
    await expectLater(ex.extract(file), dailyLimit());
    expect(inner.calls, 1);
    expect(ex.provider, inner.provider);
  });

  test('proponente: não chama o inner ao estourar', () async {
    final l = limiter(
      MemoryAiUsageStore(),
      () => DateTime(2026, 11, 10),
      limit: 1,
    );
    final inner = FakeStepProposer();
    final p = DailyLimitedStepProposer(inner, l);
    final ctx = DirectionContext(
      today: DateTime(2026, 11, 10),
      goal: const GoalSummary(exam: ExamTarget.enem, weeklyHours: 5),
      coverage: [
        const SubjectCoverage(area: Area.mathematics, subject: 'Matemática'),
      ],
    );
    await p.propose(ctx);
    await expectLater(p.propose(ctx), dailyLimit());
    expect(inner.calls, 1);
  });
}
