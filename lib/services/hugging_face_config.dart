class HuggingFaceConfig {
  const HuggingFaceConfig._();

  static Uri get chatCompletionsUri {
    return Uri.parse('https://router.huggingface.co/v1/chat/completions');
  }

  static String? modelId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;

    if (!parsed.hasScheme) {
      return trimmed;
    }

    if (parsed.host == 'huggingface.co') {
      final modelId = parsed.pathSegments.take(2).join('/');
      if (modelId.isEmpty) return null;
      return modelId;
    }

    if (parsed.host == 'api-inference.huggingface.co') {
      final segments = parsed.pathSegments;
      final modelSegments = segments.isNotEmpty && segments.first == 'models'
          ? segments.skip(1).take(2)
          : segments.take(2);
      final modelId = modelSegments.join('/');
      if (modelId.isEmpty) return null;
      return modelId;
    }

    return trimmed;
  }
}
