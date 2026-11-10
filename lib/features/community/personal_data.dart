/// Detecta texto que parece dado pessoal (telefone, e-mail ou CPF) para o
/// aviso antes de publicar (CA-C9). É só um aviso: a decisão é de quem escreve.
enum PersonalDataKind {
  email('e-mail'),
  cpf('CPF'),
  phone('telefone');

  const PersonalDataKind(this.label);
  final String label;
}

final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
final RegExp _cpf = RegExp(r'(?<!\d)\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?!\d)');
final RegExp _phone = RegExp(
  r'(?<!\d)(\+?55[\s.-]?)?\(?\d{2}\)?[\s.-]?9?\d{4}[\s.-]?\d{4}(?!\d)'
  // Sem DDD: o hífen é obrigatório (98765-4321, 3456-7890).
  r'|(?<!\d)9?\d{4}-\d{4}(?!\d)',
);

/// Tipos de dado pessoal que o [text] aparenta ter, na ordem e sem repetir.
List<PersonalDataKind> detectPersonalData(String text) {
  final found = <PersonalDataKind>[];
  if (_email.hasMatch(text)) found.add(PersonalDataKind.email);
  // Um CPF também casaria como telefone: tira antes de procurar telefone.
  final withoutCpf = text.replaceAll(_cpf, ' ');
  if (withoutCpf.length != text.length) found.add(PersonalDataKind.cpf);
  if (_phone.hasMatch(withoutCpf)) found.add(PersonalDataKind.phone);
  return found;
}
