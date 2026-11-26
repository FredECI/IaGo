import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/ai_ports.dart';
import '../community/community_access.dart';
import 'import_models.dart';

/// Escolhe arquivos para a IA. Injetável: os testes trocam por uma lista fixa.
typedef PickFiles = Future<List<ImportFile>> Function();

/// Padrão: o seletor de arquivos do sistema (prints e PDF), por
/// `file_selector`. Trocar é só sobrescrever este provider.
final pickFilesProvider = Provider<PickFiles>((ref) => pickImportFiles);

const XTypeGroup _importTypes = XTypeGroup(
  label: 'Prints e PDF',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'application/pdf'],
  uniformTypeIdentifiers: [
    'public.png',
    'public.jpeg',
    'org.webmproject.webp',
    'com.adobe.pdf',
  ],
);

Future<List<ImportFile>> pickImportFiles() async {
  final picked = await openFiles(acceptedTypeGroups: [_importTypes]);
  final files = <ImportFile>[];
  for (final x in picked) {
    // Passou do teto de arquivos ou do tamanho: não lê os bytes. Segue com
    // um arquivo sem conteúdo (ou com 1 byte a mais que o limite), que a
    // checagem de limites recusa pelo motivo certo, sem custo de memória.
    final skip = files.length >= maxImportFiles;
    final tooBig = !skip && await x.length() > maxImportFileBytes;
    files.add(
      ImportFile(
        name: x.name,
        mimeType: x.mimeType ?? '',
        bytes: skip
            ? Uint8List(0)
            : tooBig
            ? Uint8List(maxImportFileBytes + 1)
            : await x.readAsBytes(),
      ),
    );
  }
  return files;
}

/// Versão do aviso de privacidade da IA aceita nesta sessão (CA-I12).
/// A gravação no perfil (`aiNoticeVersion`) depende do campo no perfil (F6).
class AiNoticeAccepted extends Notifier<String?> {
  @override
  String? build() {
    // Outra sessão (sair/entrar) pede o aceite de novo.
    ref.watch(sessionProvider);
    return null;
  }

  void accept() => state = aiNoticeVersion;
}

final aiNoticeAcceptedProvider = NotifierProvider<AiNoticeAccepted, String?>(
  AiNoticeAccepted.new,
);

/// Modo da IA para a tela de importação.
final importAiModeProvider = Provider<ImportAiMode>((ref) {
  final session = ref.watch(sessionProvider);
  return resolveImportAiMode(
    isDemo: session?.isDemo ?? false,
    extractor: ref.watch(questionExtractorProvider),
    policy: ref.watch(accessPolicyProvider),
    isMember: ref.watch(isMemberProvider),
  );
});
