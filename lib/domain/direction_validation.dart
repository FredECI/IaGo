import 'area.dart';
import 'direction_models.dart';

/// Resultado da conferência de uma proposta. Vazio de [violations] = válida.
class ProposalValidation {
  const ProposalValidation(this.violations, [this.steps = const []]);

  /// Motivos técnicos (para log; não vão para a tela).
  final List<String> violations;

  /// Etapas lidas; só preenchido quando válida.
  final List<ProposedStep> steps;

  bool get isValid => violations.isEmpty;
}

/// Confere uma proposta (das regras ou da IA) contra a C.2 da spec: de 1 a 3
/// etapas; matéria no catálogo da área; `targetCount` de 1 a 30; `dueInDays`
/// de 1 a 14, crescente, com intervalo mínimo; sem matéria repetida;
/// `rationale` de até 140 caracteres. Qualquer violação invalida tudo.
///
/// Prefira [validateProposalFor], que usa os limites do contexto. O padrão de
/// [limits] existe só por compatibilidade; quem monta o pedido com limites
/// próprios deve passá-los aqui.
ProposalValidation validateProposal(
  List<ProposedStep> steps, {
  DirectionLimits limits = const DirectionLimits(),
}) {
  final v = <String>[];
  if (steps.isEmpty || steps.length > limits.maxSteps) {
    v.add('quantidade de etapas fora de 1..${limits.maxSteps}');
  }
  final seen = <String>{};
  int? previousDue;
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    if (!s.area.subjects.contains(s.subject)) {
      v.add('etapa $i: matéria fora do catálogo');
    }
    if (!seen.add(s.subject)) v.add('etapa $i: matéria repetida');
    if (s.targetCount < 1 || s.targetCount > limits.maxTargetCount) {
      v.add('etapa $i: targetCount fora do limite');
    }
    if (s.dueInDays < 1 || s.dueInDays > limits.maxDaysAhead) {
      v.add('etapa $i: prazo fora do limite');
    }
    if (previousDue != null &&
        s.dueInDays - previousDue < limits.minDaysBetweenDeadlines) {
      v.add('etapa $i: prazo sem o intervalo mínimo');
    }
    previousDue = s.dueInDays;
    if (s.rationale.trim().isEmpty ||
        s.rationale.length > limits.maxRationaleLength) {
      v.add('etapa $i: rationale vazio ou longo demais');
    }
  }
  return ProposalValidation(v, v.isEmpty ? List.unmodifiable(steps) : const []);
}

/// Lê e confere o JSON já decodificado (formato da C.2). Campos extras, como
/// gabarito, são ignorados. Qualquer campo faltando ou de tipo errado
/// invalida a resposta inteira. Nunca lança.
ProposalValidation validateProposalJson(
  Object? json, {
  DirectionLimits limits = const DirectionLimits(),
}) {
  if (json is! Map) return const ProposalValidation(['raiz não é objeto']);
  if (json['schemaVersion'] != 1) {
    return const ProposalValidation(['schemaVersion inesperada']);
  }
  final raw = json['steps'];
  if (raw is! List) return const ProposalValidation(['steps não é lista']);
  final steps = <ProposedStep>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) return ProposalValidation(['etapa $i: não é objeto']);
    final action = StepAction.tryParse(item['action']);
    final rawArea = item['area'];
    final area = Area.tryParse(rawArea is String ? rawArea : null);
    final subject = item['subject'];
    final count = item['targetCount'];
    final due = item['dueInDays'];
    final rationale = item['rationale'];
    if (action == null ||
        area == null ||
        subject is! String ||
        count is! int ||
        due is! int ||
        rationale is! String) {
      return ProposalValidation(['etapa $i: campo ausente ou de tipo errado']);
    }
    steps.add(
      ProposedStep(
        action: action,
        area: area,
        subject: subject,
        targetCount: count,
        dueInDays: due,
        rationale: rationale,
      ),
    );
  }
  return validateProposal(steps, limits: limits);
}

/// Valida contra os MESMOS limites do pedido: lidos do contexto, nunca de um
/// padrão implícito.
ProposalValidation validateProposalFor(
  DirectionContext context,
  List<ProposedStep> steps,
) => validateProposal(steps, limits: context.limits);

/// Versão JSON de [validateProposalFor].
ProposalValidation validateProposalJsonFor(
  DirectionContext context,
  Object? json,
) => validateProposalJson(json, limits: context.limits);
