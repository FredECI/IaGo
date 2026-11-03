import 'package:intl/intl.dart';

/// Formatação de datas e contagens em português do Brasil.
abstract final class Formatters {
  static final DateFormat _dayMonth = DateFormat("d 'de' MMM", 'pt_BR');
  static final DateFormat _full = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
  static final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

  /// "hoje", "ontem", "há 3 dias" ou "12 de out.".
  static String relativeDay(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'ontem';
    if (days < 7) return 'há $days dias';
    return _dayMonth.format(date);
  }

  static String dateTime(DateTime date) => _full.format(date);

  static String date(DateTime date) => _date.format(date);

  /// "1 questão", "2 questões".
  static String count(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';

  static String questions(int n) => count(n, 'questão', 'questões');
}
