import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências locais do aparelho (tema). `null` se o navegador bloquear.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Inicialização comum ao app e aos testes: datas em pt-BR e preferências.
Future<List<Override>> bootstrap() async {
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null;
  }
  return [sharedPreferencesProvider.overrideWithValue(prefs)];
}
