class OpenClawModel {
  final String provider;
  final String id;
  final String name;
  final bool reasoning;
  final List<String> input;

  const OpenClawModel({
    required this.provider,
    required this.id,
    required this.name,
    this.reasoning = false,
    this.input = const [],
  });

  String get modelRef => '$provider/$id';
  String get displayName => name.trim().isEmpty ? id : name;
  String get providerLabel => switch (provider.toLowerCase()) {
    'deepseek' => '深度求索',
    'openai' => 'OpenAI',
    'qwen' => '通义千问',
    'moonshot' => '月之暗面',
    _ => provider,
  };

  String get capabilityLabel {
    final capabilities = <String>[];
    if (reasoning) capabilities.add('推理');
    if (input.contains('image')) capabilities.add('视觉');
    return capabilities.isEmpty ? '文本' : capabilities.join(' · ');
  }
}
