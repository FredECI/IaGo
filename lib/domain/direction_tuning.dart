/// Janela única, em dias, das contagens do Direciona (`savedLast14d`,
/// `listsExportedLast14d`, `doneLast14d`...). Os nomes do contrato C.2 ficam
/// como estão; só o valor vem daqui.
const int directionWindowDays = 14;

/// Todos os parâmetros do planejador por regras num só lugar. Os valores
/// padrão são o comportamento documentado na spec; trocar um valor é mudar
/// só esta classe (ou passar outra instância a `planDirection`).
class PlannerTuning {
  const PlannerTuning({
    this.minQuestionsPerSubject = 10,
    this.minCollectTarget = 5,
    this.maxCollectTarget = 10,
    this.buildListTarget = 10,
    this.practiceTarget = 10,
    this.reviewTarget = 8,
    this.minutesPerCollect = 3,
    this.minutesPerBuildList = 1,
    this.minutesPerPractice = 4,
    this.minutesPerReview = 3,
    this.minDays = 2,
    this.maxDays = 7,
    this.dailyShareDivisor = 3,
  });

  /// Abaixo disto a ação da matéria é `collect`.
  final int minQuestionsPerSubject;

  /// Meta de `collect`: completa até [minQuestionsPerSubject], limitada a
  /// este intervalo (evita metas pequenas demais).
  final int minCollectTarget;
  final int maxCollectTarget;

  /// Metas das demais ações.
  final int buildListTarget;
  final int practiceTarget;
  final int reviewTarget;

  /// Minutos por questão, por ação (estimativa de esforço).
  final int minutesPerCollect;
  final int minutesPerBuildList;
  final int minutesPerPractice;
  final int minutesPerReview;

  /// Prazo calculado, em dias, limitado a este intervalo.
  final int minDays;
  final int maxDays;

  /// A etapa usa 1/[dailyShareDivisor] do tempo diário de estudo.
  final int dailyShareDivisor;
}
