/// Leitura de `appConfig/runtime` (só leitura; quem escreve é o console).
///
/// Devolve o documento cru. Só `AccessPolicy.fromRuntime` o interpreta
/// (CA-R1). `null` significa "sem configuração" (documento ausente, sem rede
/// ou erro), e o padrão seguro da política passa a valer.
abstract interface class RuntimeConfigRepository {
  Future<Map<String, Object?>?> load();
}
