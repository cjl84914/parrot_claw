import 'package:hive_flutter/hive_flutter.dart';

/// 扫码配对成功后，把网关实际授权的 operator scopes 按端点持久化。
///
/// 背景：扫码 bootstrap 走的是"受限"授权（无 operator.admin/pairing）。
/// 若重连时仍按默认全量 operator scope 请求，会再次触发 scope-upgrade 审批。
/// 这里按 wsUrl 存一份 scopes，重连时显式带上，与配对时保持一致。
class GatewayScopeStore {
  GatewayScopeStore._();

  static const String _boxName = 'gateway_meta';
  static const String _operatorScopePrefix = 'operator_scopes:';

  static Future<Box> _box() => Hive.openBox(_boxName);

  /// 返回该端点持久化的 operator scopes；无记录返回 null（保持原默认行为）。
  static Future<List<String>?> operatorScopes(String wsUrl) async {
    try {
      final box = await _box();
      final raw = box.get('$_operatorScopePrefix$wsUrl');
      if (raw is List) {
        final scopes = raw
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (scopes.isNotEmpty) return scopes;
      }
    } catch (_) {
      // 读失败不影响主流程，按无记录处理。
    }
    return null;
  }

  /// 记录该端点实际授权的 operator scopes；传 null 时删除记录。
  static Future<void> saveOperatorScopes(String wsUrl, List<String>? scopes) async {
    try {
      final box = await _box();
      final key = '$_operatorScopePrefix$wsUrl';
      if (scopes == null || scopes.isEmpty) {
        if (box.containsKey(key)) {
          await box.delete(key);
        }
        return;
      }
      await box.put(key, scopes);
    } catch (_) {
      // 落盘失败不阻断配对主流程。
    }
  }
}
