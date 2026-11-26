/// Limites da proposta do Direciona pela IA (CA-R7): uma linha para mudar
/// cada um. Dart puro.
library;

/// Propostas pela IA por usuário, na janela [aiProposalWindow].
const int maxAiProposalsPerWindow = 1;

/// A janela do limite: "no máximo uma vez por semana".
const Duration aiProposalWindow = Duration(days: 7);

/// Espera máxima pela IA antes de cair nas regras (tabela da spec: 20 s).
const Duration aiProposalTimeout = Duration(seconds: 20);

/// Distância mínima entre duas propostas pela IA. Com um só registro
/// (`StudyGoal.lastAiAt`), o limite vira um intervalo: a janela dividida pelo
/// número de propostas permitidas.
Duration get aiProposalMinInterval =>
    aiProposalWindow ~/ maxAiProposalsPerWindow;

/// A IA pode propor agora? `lastAiAt` é a última proposta pela IA (`null` =
/// nunca). Relógio do aparelho que volte no tempo não trava para sempre: o
/// que está no futuro conta como liberado.
bool aiProposalAllowed(DateTime? lastAiAt, DateTime now) {
  if (lastAiAt == null || lastAiAt.isAfter(now)) return true;
  return now.difference(lastAiAt) >= aiProposalMinInterval;
}
