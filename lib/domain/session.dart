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

/// Conta real (Firebase Auth). A igualdade inclui o nome, para a saudação
/// atualizar quando o perfil muda; os repositórios dependem só do `uid`
/// (veja `dataOwnerProvider`).
final class AccountSession extends Session {
  const AccountSession({required this.uid, required this.email, this.name});

  final String uid;
  final String email;
  final String? name;

  @override
  String get displayName {
    final first = (name ?? '').trim().split(' ').first;
    return first.isNotEmpty ? first : email.split('@').first;
  }

  @override
  bool get isDemo => false;

  @override
  bool operator ==(Object other) =>
      other is AccountSession &&
      other.uid == uid &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(uid, email, name);
}
