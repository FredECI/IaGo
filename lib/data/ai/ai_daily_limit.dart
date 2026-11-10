/// Limite suave de chamadas de IA por usuário e por dia (`aiDailyPerUser`).
///
/// É o ponto único do limite (CA-R7, "Toda limitação é reversível"): as duas
/// portas de IA reais são embrulhadas aqui, e as telas só tratam
/// [AiFailure.dailyLimit]. Desfazer é tirar os dois embrulhos de
/// `policy_providers.dart`. A contagem mora no aparelho (SharedPreferences,
/// ou memória se ele não existir), por isso é "suave": limpar os dados do
/// navegador zera. Quem protege a cota de verdade é o App Check.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/ai_ports.dart';
import '../../domain/direction_models.dart';
import '../../domain/extraction_contract.dart';

/// Guarda quantas chamadas cada usuário fez em cada dia local.
abstract interface class AiUsageStore {
  /// Chamadas de [owner] em [day] (`AAAA-MM-DD`).
  int usedOn(String owner, String day);
  void record(String owner, String day);
}

/// Em memória: vale na sessão (testes, ou sem SharedPreferences).
class MemoryAiUsageStore implements AiUsageStore {
  final Map<String, int> _counts = {};

  @override
  int usedOn(String owner, String day) => _counts['$owner|$day'] ?? 0;

  @override
  void record(String owner, String day) =>
      _counts.update('$owner|$day', (n) => n + 1, ifAbsent: () => 1);
}

/// No aparelho: uma chave por usuário, com `dia:contagem` (o dia velho some
/// sozinho na primeira chamada do dia seguinte).
class PrefsAiUsageStore implements AiUsageStore {
  PrefsAiUsageStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String owner) => 'ai_usage.$owner';

  @override
  int usedOn(String owner, String day) {
    final raw = _prefs.getString(_key(owner));
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0] != day) return 0;
    // Valor negativo (edição manual) não vira cota extra.
    final n = int.tryParse(parts[1]) ?? 0;
    return n < 0 ? 0 : n;
  }

  @override
  void record(String owner, String day) {
    _prefs.setString(_key(owner), '$day:${usedOn(owner, day) + 1}');
  }
}

String aiUsageDayKey(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-'
    '${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}';

/// Consulta e registra o consumo do dia.
class AiDailyLimiter {
  AiDailyLimiter({
    required this.store,
    required this.owner,
    required this.limit,
    required this.now,
  });

  final AiUsageStore store;
  final String owner;

  /// `AccessPolicy.aiDailyPerUser`.
  final int limit;
  final DateTime Function() now;

  int get usedToday => store.usedOn(owner, aiUsageDayKey(now()));
  bool get hasRoom => usedToday < limit;

  /// Reserva uma chamada ou lança [AiFailure.dailyLimit]. A reserva é gasta na
  /// hora: chamada que falha, estoura o tempo ou é cancelada na tela NÃO devolve
  /// a cota (o pedido pode ter chegado ao provedor).
  void consume() {
    if (!hasRoom) throw const AiException(AiFailure.dailyLimit);
    store.record(owner, aiUsageDayKey(now()));
  }
}

class DailyLimitedQuestionExtractor implements QuestionExtractor {
  DailyLimitedQuestionExtractor(this.inner, this.limiter);

  final QuestionExtractor inner;
  final AiDailyLimiter limiter;

  @override
  AiProviderInfo get provider => inner.provider;

  @override
  Future<ExtractionResult> extract(ImportFile file) async {
    limiter.consume();
    return await inner.extract(file);
  }
}

class DailyLimitedStepProposer implements StepProposer {
  DailyLimitedStepProposer(this.inner, this.limiter);

  final StepProposer inner;
  final AiDailyLimiter limiter;

  @override
  AiProviderInfo get provider => inner.provider;

  @override
  Future<List<ProposedStep>> propose(DirectionContext context) async {
    limiter.consume();
    return await inner.propose(context);
  }
}
