/// flutter_tts 音色（voice）相关的纯逻辑。
///
/// `getVoices()` 各平台返回的都是 `[{name, locale, ...}]`，只是字段略有差别：
/// - Android：name / locale(zh-CN) / quality / latency / network_required / features
/// - iOS、macOS：额外带 identifier，用它匹配音色最精确
/// - Windows：name / locale / gender
///
/// 平台差异集中在这里，页面只负责渲染，逻辑用单测守着。
class TtsVoiceUtil {
  const TtsVoiceUtil._();

  /// 把 `getVoices()` 的原始返回值收敛成 `List<Map<String, String>>`，
  /// 非 Map 元素直接丢弃，值统一转成字符串（平台通道可能给出非 String）。
  static List<Map<String, String>> parseVoices(dynamic rawVoices) {
    final voices = <Map<String, String>>[];
    if (rawVoices is! List) return voices;
    for (final raw in rawVoices) {
      if (raw is Map) {
        voices.add(
          raw.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        );
      }
    }
    return voices;
  }

  /// `zh_CN` / `zh-CN` / `ZH_cn` 各平台写法不统一，统一成小写 + '-'。
  static String normalizeLocale(String? locale) =>
      (locale ?? '').trim().replaceAll('_', '-').toLowerCase();

  /// 语言与音色 locale 是否属于同一门语言：完全相等，或主语言子标签一致
  /// （`zh` 能匹配 `zh-CN`、`zh-TW`）。
  static bool localeMatches(String? voiceLocale, String? language) {
    final voice = normalizeLocale(voiceLocale);
    final lang = normalizeLocale(language);
    if (voice.isEmpty || lang.isEmpty) return false;
    return voice == lang || voice.split('-').first == lang.split('-').first;
  }

  /// 音色没有跨平台稳定 id：iOS、macOS 用 identifier，其余平台用 name@locale。
  static String keyOf(Map<String, String> voice) {
    final identifier = voice['identifier'];
    if (identifier != null && identifier.isNotEmpty) return identifier;
    return '${voice['name'] ?? ''}@${voice['locale'] ?? ''}';
  }

  /// 下拉框里显示成 `Tingting (zh-CN)`。
  static String labelOf(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    if (name.isEmpty) return locale;
    return locale.isEmpty ? name : '$name ($locale)';
  }

  /// 生成下拉框实际展示的音色列表：
  /// 1. 优先只保留与 [language] 同语言的音色；
  /// 2. 一个都匹配不到时退回全部，避免下拉框空白；
  /// 3. 已选音色 [selected] 一定保留，否则下拉框会显示成「默认」而引擎其实还在用它；
  /// 4. 按 locale、name 排序，并按 [keyOf] 去重。
  static List<Map<String, String>> visibleVoices({
    required List<Map<String, String>> voices,
    String? language,
    Map<String, String>? selected,
  }) {
    var visible =
        voices
            .where((voice) => localeMatches(voice['locale'], language))
            .toList();
    if (visible.isEmpty) visible = List<Map<String, String>>.of(voices);

    if (selected != null) {
      final selectedKey = keyOf(selected);
      if (!visible.any((voice) => keyOf(voice) == selectedKey)) {
        visible.add(selected);
      }
    }

    visible.sort((a, b) {
      final byLocale = (a['locale'] ?? '').compareTo(b['locale'] ?? '');
      if (byLocale != 0) return byLocale;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });

    final seenKeys = <String>{};
    return visible.where((voice) => seenKeys.add(keyOf(voice))).toList();
  }
}
