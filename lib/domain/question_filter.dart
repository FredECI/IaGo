import '../core/text_normalizer.dart';
import 'area.dart';
import 'question.dart';

const Object _unset = Object();

/// Dimensões de filtro da tela de questões.
enum FilterDimension { area, subject, topic, type, platform }

/// Busca por texto + filtros por área, matéria, assunto, tipo e plataforma.
///
/// Dentro de uma dimensão as opções se somam (OU); entre dimensões, todas
/// precisam valer (E). Assunto e plataforma são comparados por [tagKey].
class QuestionFilter {
  const QuestionFilter({
    this.query = '',
    this.areas = const {},
    this.subjects = const {},
    this.topicKeys = const {},
    this.type,
    this.platformKeys = const {},
  });

  final String query;
  final Set<Area> areas;
  final Set<String> subjects;
  final Set<String> topicKeys;
  final QuestionType? type;
  final Set<String> platformKeys;

  bool get hasQuery => query.trim().isNotEmpty;

  bool get hasFilters =>
      areas.isNotEmpty ||
      subjects.isNotEmpty ||
      topicKeys.isNotEmpty ||
      type != null ||
      platformKeys.isNotEmpty;

  bool get isEmpty => !hasQuery && !hasFilters;

  QuestionFilter copyWith({
    String? query,
    Set<Area>? areas,
    Set<String>? subjects,
    Set<String>? topicKeys,
    Object? type = _unset,
    Set<String>? platformKeys,
  }) {
    return QuestionFilter(
      query: query ?? this.query,
      areas: areas ?? this.areas,
      subjects: subjects ?? this.subjects,
      topicKeys: topicKeys ?? this.topicKeys,
      type: identical(type, _unset) ? this.type : type as QuestionType?,
      platformKeys: platformKeys ?? this.platformKeys,
    );
  }

  QuestionFilter toggleArea(Area area) => copyWith(areas: _toggle(areas, area));

  QuestionFilter toggleSubject(String subject) =>
      copyWith(subjects: _toggle(subjects, subject));

  QuestionFilter toggleTopic(String topicKey) =>
      copyWith(topicKeys: _toggle(topicKeys, topicKey));

  QuestionFilter togglePlatform(String platformKey) =>
      copyWith(platformKeys: _toggle(platformKeys, platformKey));

  /// Seleciona o tipo; tocar de novo no mesmo tipo limpa o filtro.
  QuestionFilter toggleType(QuestionType value) =>
      copyWith(type: type == value ? null : value);

  /// Limpa os filtros e mantém o texto da busca.
  QuestionFilter clearFilters() => QuestionFilter(query: query);

  /// A questão passa na busca e nos filtros? [ignoring] deixa uma dimensão de
  /// fora, para calcular os contadores daquela dimensão.
  bool matches(
    Question question, {
    FilterDimension? ignoring,
    List<String>? terms,
  }) {
    for (final term in terms ?? searchTerms(query)) {
      if (!question.searchText.contains(term)) return false;
    }
    if (ignoring != FilterDimension.area &&
        areas.isNotEmpty &&
        !areas.contains(question.area)) {
      return false;
    }
    if (ignoring != FilterDimension.subject &&
        subjects.isNotEmpty &&
        !subjects.contains(question.subject)) {
      return false;
    }
    if (ignoring != FilterDimension.topic &&
        topicKeys.isNotEmpty &&
        !topicKeys.contains(question.topicKey)) {
      return false;
    }
    if (ignoring != FilterDimension.type &&
        type != null &&
        question.type != type) {
      return false;
    }
    if (ignoring != FilterDimension.platform &&
        platformKeys.isNotEmpty &&
        !platformKeys.contains(question.platformKey)) {
      return false;
    }
    return true;
  }

  /// Aplica busca e filtros mantendo a ordem original.
  List<Question> apply(List<Question> questions) {
    final terms = searchTerms(query);
    return [
      for (final q in questions)
        if (matches(q, terms: terms)) q,
    ];
  }

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  bool operator ==(Object other) =>
      other is QuestionFilter &&
      other.query == query &&
      _setEquals(other.areas, areas) &&
      _setEquals(other.subjects, subjects) &&
      _setEquals(other.topicKeys, topicKeys) &&
      other.type == type &&
      _setEquals(other.platformKeys, platformKeys);

  @override
  int get hashCode => Object.hash(
    query,
    Object.hashAllUnordered(areas),
    Object.hashAllUnordered(subjects),
    Object.hashAllUnordered(topicKeys),
    type,
    Object.hashAllUnordered(platformKeys),
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Opção de filtro com o rótulo exibido e quantas questões ela traria.
class FacetOption<T> {
  const FacetOption({
    required this.value,
    required this.label,
    required this.count,
    required this.selected,
  });

  final T value;
  final String label;
  final int count;
  final bool selected;
}

/// Contadores por filtro (facetas): cada contador considera a busca e os
/// filtros das outras dimensões, como em lojas online.
class QuestionFacets {
  const QuestionFacets({
    required this.areas,
    required this.subjects,
    required this.topics,
    required this.types,
    required this.platforms,
  });

  /// Sempre as quatro áreas, na ordem do catálogo.
  final List<FacetOption<Area>> areas;
  final List<FacetOption<String>> subjects;

  /// Valor = [tagKey] do assunto; rótulo = grafia mais recente.
  final List<FacetOption<String>> topics;

  /// Sempre os dois tipos.
  final List<FacetOption<QuestionType>> types;

  /// Valor = [tagKey] da plataforma.
  final List<FacetOption<String>> platforms;

  factory QuestionFacets.compute(
    List<Question> questions,
    QuestionFilter filter,
  ) {
    final terms = searchTerms(filter.query);
    final areaCounts = <Area, int>{};
    final subjectCounts = <String, int>{};
    final topicCounts = <String, int>{};
    final typeCounts = <QuestionType, int>{};
    final platformCounts = <String, int>{};
    final topicLabels = <String, String>{};
    final platformLabels = <String, String>{};

    for (final q in questions) {
      if (q.topicKey.isNotEmpty) {
        topicLabels.putIfAbsent(q.topicKey, () => q.topic.trim());
      }
      if (q.platformKey.isNotEmpty) {
        platformLabels.putIfAbsent(q.platformKey, () => q.platform.trim());
      }
      bool passes(FilterDimension d) =>
          filter.matches(q, ignoring: d, terms: terms);
      if (passes(FilterDimension.area)) {
        areaCounts.update(q.area, (n) => n + 1, ifAbsent: () => 1);
      }
      if (passes(FilterDimension.subject)) {
        subjectCounts.update(q.subject, (n) => n + 1, ifAbsent: () => 1);
      }
      if (q.topicKey.isNotEmpty && passes(FilterDimension.topic)) {
        topicCounts.update(q.topicKey, (n) => n + 1, ifAbsent: () => 1);
      }
      if (passes(FilterDimension.type)) {
        typeCounts.update(q.type, (n) => n + 1, ifAbsent: () => 1);
      }
      if (q.platformKey.isNotEmpty && passes(FilterDimension.platform)) {
        platformCounts.update(q.platformKey, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    List<FacetOption<String>> ranked(
      Map<String, int> counts,
      Set<String> selected,
      String Function(String) label,
    ) {
      final keys = {...counts.keys, ...selected}.toList()
        ..sort((a, b) {
          final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          return byCount != 0 ? byCount : label(a).compareTo(label(b));
        });
      return [
        for (final key in keys)
          FacetOption(
            value: key,
            label: label(key),
            count: counts[key] ?? 0,
            selected: selected.contains(key),
          ),
      ];
    }

    return QuestionFacets(
      areas: [
        for (final area in Area.values)
          FacetOption(
            value: area,
            label: area.shortLabel,
            count: areaCounts[area] ?? 0,
            selected: filter.areas.contains(area),
          ),
      ],
      subjects: ranked(subjectCounts, filter.subjects, (s) => s),
      topics: ranked(topicCounts, filter.topicKeys, (k) => topicLabels[k] ?? k),
      types: [
        for (final type in QuestionType.values)
          FacetOption(
            value: type,
            label: type.label,
            count: typeCounts[type] ?? 0,
            selected: filter.type == type,
          ),
      ],
      platforms: ranked(
        platformCounts,
        filter.platformKeys,
        (k) => platformLabels[k] ?? k,
      ),
    );
  }
}
