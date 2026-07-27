class StringUtil {
  static String cleanTextForTts(String text) {
    // 移除或替换特殊字符
    String cleaned = text
        // 移除网址 - 匹配各种网址格式
        .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false),
            '') // http://和https://开头的网址
        .replaceAll(
            RegExp(r'www\.[^\s]+', caseSensitive: false), '') // www.开头的网址
        .replaceAll(
            RegExp(r'[a-zA-Z0-9-]+\.[a-zA-Z]{2,}[^\s]*', caseSensitive: false),
            '') // 一般域名格式
        .replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
            '') // 邮箱地址
        .replaceAll(RegExp(r'\([^\s]+\)', caseSensitive: false), '')
        // 移除星号
        .replaceAll('*', '')
        // 移除下划线
        .replaceAll('_', '')
        // 移除井号
        .replaceAll('#', '')
        // 移除反引号
        .replaceAll('`', '')
        // 移除方括号
        .replaceAll('[', '')
        .replaceAll(']', '')
        // 移除花括号
        .replaceAll('{', '')
        .replaceAll('}', '')
        // 移除竖线
        .replaceAll('|', '')
        // 移除反斜杠
        .replaceAll('\\', '')
        // 移除emoji字符
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '') // 表情符号
        .replaceAll(
            RegExp(r'[\u{1F300}-\u{1F5FF}]', unicode: true), '') // 符号和象形图
        .replaceAll(
            RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '') // 交通和地图符号
        .replaceAll(RegExp(r'[\u{1F1E0}-\u{1F1FF}]', unicode: true), '') // 国旗
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '') // 杂项符号
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '') // 装饰符号
        .replaceAll(
            RegExp(r'[\u{1F900}-\u{1F9FF}]', unicode: true), '') // 补充符号和象形图
        .replaceAll(
            RegExp(r'[\u{1FA70}-\u{1FAFF}]', unicode: true), '') // 扩展A符号和象形图
        // 移除多余的空格和换行
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned;
  }
}
