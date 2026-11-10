import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/firebase_config.dart';
import '../../../domain/ai_ports.dart';
import 'ai_error_translation.dart';
import 'ai_gateway.dart';
import 'app_check_setup.dart';

/// Gateway de verdade: Firebase AI Logic (Gemini Developer API) com App
/// Check. Sem chave de API da Gemini no app: quem autoriza é o App Check.
class FirebaseAiGateway implements AiGateway {
  FirebaseAiGateway({
    this.ensureAppCheck = ensureAppCheckActivated,
    this.configured = _isConfigured,
  });

  /// Injetáveis nos testes. O App Check é ativado aqui, na primeira
  /// necessidade, e não na abertura do app (a demo não toca nele).
  final Future<AppCheckOutcome> Function() ensureAppCheck;
  final bool Function() configured;

  static bool _isConfigured() =>
      FirebaseConfig.isConfigured &&
      !FirebaseConfig.usesEmulator &&
      Firebase.apps.isNotEmpty;

  @override
  Future<AiAvailability> availability() async {
    if (!configured()) return AiAvailability.firebaseUnavailable;
    return (await ensureAppCheck()).isActive
        ? AiAvailability.available
        : AiAvailability.appCheckUnavailable;
  }

  @override
  Future<String> generateJson({
    required AiCall call,
    required String model,
    required String systemInstruction,
    required String prompt,
    List<ImportFile> files = const [],
    required Map<String, Object?> responseSchema,
    required Duration timeout,
  }) async {
    try {
      await ensureAppCheck();
      final generative = FirebaseAI.googleAI().generativeModel(
        model: model,
        systemInstruction: Content.system(systemInstruction),
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
          responseSchema: _toSchema(responseSchema),
        ),
      );
      final response = await generative
          .generateContent([
            Content.multi([
              TextPart(prompt),
              for (final f in files) InlineDataPart(f.mimeType, f.bytes),
            ]),
          ])
          .timeout(timeout);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw const AiException(AiFailure.malformed);
      }
      return text;
    } catch (e) {
      throw translateAiError(e);
    }
  }
}

/// Converte o esquema em mapas (`ai_schemas.dart`) no `Schema` do SDK.
Schema _toSchema(Map<String, Object?> m) {
  final nullable = m['nullable'] == true ? true : null;
  switch (m['type']) {
    case 'object':
      final props = (m['properties'] as Map).cast<String, Object?>();
      return Schema.object(
        properties: {
          for (final e in props.entries)
            e.key: _toSchema((e.value as Map).cast<String, Object?>()),
        },
        nullable: nullable,
      );
    case 'array':
      return Schema.array(
        items: _toSchema((m['items'] as Map).cast<String, Object?>()),
        nullable: nullable,
      );
    case 'integer':
      return Schema.integer(nullable: nullable);
    case 'boolean':
      return Schema.boolean(nullable: nullable);
    case 'string':
      final values = m['enum'];
      return values is List
          ? Schema.enumString(
              enumValues: values.cast<String>(),
              nullable: nullable,
            )
          : Schema.string(nullable: nullable);
  }
  throw ArgumentError('Tipo de esquema desconhecido: ${jsonEncode(m['type'])}');
}
