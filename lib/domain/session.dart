/// Quem está usando o app agora.
sealed class Session {
  const Session();

  String get displayName;

  /// Na demonstração os dados são locais e nada vai para o servidor.
  bool get isDemo;
}

/// Modo demonstração: conta do Pedro com dados de exemplo, sem internet.
///
/// Cada entrada cria uma sessão nova (sem `==` por valor), o que recria os
/// dados de exemplo do zero: estado limpo e previsível em todo ensaio.
final class DemoSession extends Session {
  const DemoSession({required this.startedAt});

  final DateTime startedAt;

  @override
  String get displayName => 'Pedro';

  @override
  bool get isDemo => true;
}
