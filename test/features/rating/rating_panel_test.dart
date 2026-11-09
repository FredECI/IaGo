import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/rating_repository.dart';
import 'package:iago/domain/rating_models.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/features/rating/rating_panel.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:iago/features/rating/rating_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_bank_catalog.dart';
import '../../helpers/test_app.dart';

/// Repositório controlável: o resumo, a falha e as chamadas.
class _FakeRatings implements RatingRepository {
  RatingValue? mine;
  RatingStats question = const RatingStats(count: 0, difficulty: 0, quality: 0);
  bool simulated = false;
  bool offline = false;
  final List<String> calls = [];

  @override
  Future<RatingValue?> myRating(String bankId) async => mine;

  @override
  Future<void> rate(RatingTarget target, RatingValue value) async {
    calls.add('rate:${value.difficulty}/${value.quality}');
    mine = value;
  }

  @override
  Future<void> remove(String bankId) async {
    calls.add('remove');
    mine = null;
  }

  @override
  Future<RatingSummary> summary(RatingTarget target) async {
    if (offline) throw const RatingFailure.offline();
    return RatingSummary(
      question: question,
      group: const RatingStats(count: 20, difficulty: 1.9, quality: 2.1),
      groupLabel: target.group,
      simulated: simulated,
    );
  }

  @override
  Future<void> setPrivateRating(
    String questionId, {
    int? difficulty,
    int? quality,
  }) async {}
}

class _DeniedRatings extends _FakeRatings {
  int reads = 0;

  @override
  Future<RatingSummary> summary(RatingTarget target) async {
    reads++;
    throw const RatingFailure(RatingFailureKind.denied);
  }

  @override
  Future<RatingValue?> myRating(String bankId) async {
    reads++;
    throw const RatingFailure(RatingFailureKind.denied);
  }
}

class _AccountController extends SessionController {
  @override
  Session? build() => const AccountSession(uid: 'u1', email: 'a@b.c');
}

void main() {
  setUpAll(initTestLocale);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  Future<void> open(
    WidgetTester tester,
    _FakeRatings ratings, {
    bool member = true,
    MemoryMetricsRepository? metrics,
  }) async {
    await pumpIagoApp(
      tester,
      overrides: [
        bankCatalogProvider.overrideWithValue(FakeBankCatalog()),
        ratingRepositoryProvider.overrideWithValue(ratings),
        isMemberProvider.overrideWithValue(member),
        if (metrics != null)
          metricsRepositoryProvider.overrideWithValue(metrics),
      ],
    );
    await enterDemo(tester);
    containerOf(tester).read(routerProvider).go('/questoes/acervo/enem-2022-3');
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tapVisible(tester, find.byKey(Key(key)));

  group('acervo: painel de avaliação', () {
    testWidgets('avalia, altera e remove', (tester) async {
      final ratings = _FakeRatings();
      await open(tester, ratings);
      await reveal(tester, find.byKey(const Key('rating-panel')));

      // Sem as duas notas, o botão fica desligado.
      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('rate-submit')));
      expect(submit().onPressed, isNull);

      await tapKey(tester, 'rate-difficulty-3');
      await tapKey(tester, 'rate-quality-2');
      await tapKey(tester, 'rate-submit');
      expect(ratings.calls, ['rate:3/2']);
      expect(find.text('Alterar avaliação'), findsOneWidget);

      await tapKey(tester, 'rate-quality-3');
      await tapKey(tester, 'rate-submit');
      expect(ratings.calls, ['rate:3/2', 'rate:3/3']);

      await tapKey(tester, 'rate-remove');
      expect(ratings.calls.last, 'remove');
      expect(find.byKey(const Key('rate-remove')), findsNothing);
      expect(find.text('Avaliar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('registra rating_saved só com bankId e notas', (tester) async {
      final metrics = MemoryMetricsRepository(clock: () => testNow);
      await open(tester, _FakeRatings(), metrics: metrics);
      await tapKey(tester, 'rate-difficulty-1');
      await tapKey(tester, 'rate-quality-3');
      await tapKey(tester, 'rate-submit');
      final e = metrics.logged
          .where((e) => e.type == MetricEventType.ratingSaved)
          .single;
      expect(e.data, {'bankId': 'enem-2022-3', 'difficulty': 1, 'quality': 3});
    });

    testWidgets('com 3 ou mais avaliações mostra o resumo relativo', (
      tester,
    ) async {
      final ratings = _FakeRatings()
        ..question = const RatingStats(count: 7, difficulty: 2.4, quality: 2.6);
      await open(tester, ratings);
      await reveal(tester, find.byKey(const Key('rating-panel')));
      expect(
        find.textContaining('Mais difícil que a média de'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Melhor avaliada que a média de'),
        findsOneWidget,
      );
      expect(find.text('Poucas avaliações ainda'), findsNothing);
      expect(find.byKey(const Key('rating-simulated')), findsNothing);
    });

    testWidgets('com menos de 3 mostra "Poucas avaliações ainda"', (
      tester,
    ) async {
      final ratings = _FakeRatings()
        ..question = const RatingStats(count: 2, difficulty: 3, quality: 3);
      await open(tester, ratings);
      await reveal(tester, find.byKey(const Key('rating-panel')));
      expect(find.text('Poucas avaliações ainda'), findsOneWidget);
      expect(find.byKey(const Key('rating-diff')), findsNothing);
    });

    testWidgets('dados simulados ganham o selo (CA-A7)', (tester) async {
      final ratings = _FakeRatings()..simulated = true;
      await open(tester, ratings);
      await reveal(tester, find.byKey(const Key('rating-panel')));
      expect(find.text('Dados simulados'), findsOneWidget);
    });

    testWidgets('sem rede mostra a mensagem e permite tentar de novo', (
      tester,
    ) async {
      final ratings = _FakeRatings()..offline = true;
      await open(tester, ratings);
      await reveal(tester, find.byKey(const Key('rating-panel')));
      expect(find.text('Avaliações indisponíveis sem conexão'), findsOneWidget);

      ratings.offline = false;
      await tapKey(tester, 'rating-retry');
      expect(find.text('Poucas avaliações ainda'), findsOneWidget);
      expect(find.byKey(const Key('rating-error')), findsNothing);
    });

    testWidgets('conta real que não é membro: nenhuma leitura nem erro', (
      tester,
    ) async {
      final ratings = _DeniedRatings();
      final q = fakeBankData().questions.first;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_AccountController.new),
            ratingRepositoryProvider.overrideWithValue(ratings),
            isMemberProvider.overrideWithValue(false),
            conectaJoinableProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            home: Scaffold(body: BankRatingPanel(question: q)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ratings.reads, 0);
      expect(find.byKey(const Key('rating-error')), findsNothing);
      expect(find.textContaining('Não foi possível'), findsNothing);
      expect(find.byKey(const Key('rating-members-note')), findsOneWidget);
      expect(find.byKey(const Key('rate-difficulty-1')), findsNothing);
      expect(find.byKey(const Key('rate-join')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Minhas questões: avaliação privada', () {
    testWidgets('grava as notas sem marcar a questão como editada', (
      tester,
    ) async {
      await pumpIagoApp(tester);
      await enterDemo(tester);
      final c = containerOf(tester);
      final before = c.read(questionsProvider).value!.first;
      c.read(routerProvider).go(Routes.question(before.id));
      await tester.pumpAndSettle();

      await tapKey(tester, 'private-difficulty-2');
      await tapKey(tester, 'private-quality-3');
      var q = c.read(questionByIdProvider(before.id))!;
      expect(q.myDifficulty, 2);
      expect(q.myQuality, 3);
      expect(q.updatedAt, before.updatedAt);
      expect(find.textContaining('Editada em'), findsNothing);

      // Tocar de novo na nota escolhida a apaga; a outra continua.
      await tapKey(tester, 'private-difficulty-2');
      q = c.read(questionByIdProvider(before.id))!;
      expect(q.myDifficulty, isNull);
      expect(q.myQuality, 3);
      expect(q.updatedAt, before.updatedAt);
      expect(tester.takeException(), isNull);
    });
  });
}
