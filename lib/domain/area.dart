/// Áreas do conhecimento (padrão ENEM), com o catálogo fixo de matérias.
///
/// Hierarquia da categorização: área → matéria → assunto (tag livre).
enum Area {
  languages(
    label: 'Linguagens',
    shortLabel: 'Linguagens',
    subjects: [
      'Português',
      'Literatura',
      'Redação',
      'Inglês',
      'Espanhol',
      'Artes',
      'Educação Física',
    ],
  ),
  humanities(
    label: 'Ciências Humanas',
    shortLabel: 'Humanas',
    subjects: ['História', 'Geografia', 'Filosofia', 'Sociologia'],
  ),
  naturalSciences(
    label: 'Ciências da Natureza',
    shortLabel: 'Natureza',
    subjects: ['Biologia', 'Física', 'Química'],
  ),
  mathematics(
    label: 'Matemática',
    shortLabel: 'Matemática',
    subjects: ['Matemática'],
  );

  const Area({
    required this.label,
    required this.shortLabel,
    required this.subjects,
  });

  final String label;
  final String shortLabel;
  final List<String> subjects;

  /// Matéria preenchida sozinha quando a área só tem uma (ex.: Matemática).
  String? get defaultSubject => subjects.length == 1 ? subjects.single : null;

  static Area? tryParse(String? name) {
    for (final area in values) {
      if (area.name == name) return area;
    }
    return null;
  }
}
