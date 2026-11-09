import '../runtime_config_repository.dart';

/// Configuração em memória, para a demo e os testes. [data] pode mudar entre
/// leituras, para simular o console.
class MemoryRuntimeConfig implements RuntimeConfigRepository {
  MemoryRuntimeConfig([this.data]);

  Map<String, Object?>? data;

  @override
  Future<Map<String, Object?>?> load() async => data;
}
