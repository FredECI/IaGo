import 'direction_models.dart';

/// Título do evento na agenda: "IaGo: Praticar 10 · Matemática".
String stepCalendarTitle(StudyStep step) =>
    'IaGo: ${step.action.label} ${step.targetCount} · ${step.subject}';

/// Link "Adicionar à agenda" (Google Agenda) para o prazo da etapa, como
/// evento de dia inteiro no dia do prazo. O formato `render?action=TEMPLATE`
/// não é um contrato oficial (R26): se mudar, o Painel segue como lembrete.
///
/// Função pura: nada de rede nem de relógio.
Uri stepCalendarUri(StudyStep step) {
  final due = step.dueAt;
  final start = DateTime(due.year, due.month, due.day);
  // Em evento de dia inteiro, o fim é exclusivo: o dia seguinte.
  final end = DateTime(due.year, due.month, due.day + 1);
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': stepCalendarTitle(step),
    'dates': '${_ymd(start)}/${_ymd(end)}',
    'details': step.rationale,
  });
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';
