import 'package:flutter/foundation.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';

/// Skill 管理的界面状态。
///
/// 直接依赖全局 [OpenClawRuntime] 单例，由 ViewModel 负责参数校验、
/// 结果解析和 loading/error 状态，不再经过额外的 Repository 层。
class SkillViewModel extends ChangeNotifier {
  SkillViewModel({OpenClawRuntime? runtime})
    : _runtime = runtime ?? OpenClawRuntime.instance;

  final OpenClawRuntime _runtime;
  List<GatewaySkill> _skills = const [];
  bool _isLoading = false;
  String? _error;
  String? _lastOperation;

  List<GatewaySkill> get skills => List.unmodifiable(_skills);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get lastOperation => _lastOperation;

  Future<bool> load() async {
    if (_isLoading) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _skills =
          GatewaySkillsStatus.fromJson(await _runtime.skillsStatus()).skills;
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> install({
    required String name,
    required String installId,
    bool? dangerouslyForceUnsafeInstall,
  }) async {
    if (_isLoading) return false;
    return _runOperation('install', () async {
      await _runtime.skillsInstall(
        name: name,
        installId: installId,
        dangerouslyForceUnsafeInstall: dangerouslyForceUnsafeInstall,
      );
      await _reload();
    });
  }

  Future<bool> update({
    required String skillKey,
    bool? enabled,
    String? apiKey,
    Map<String, String>? env,
  }) async {
    if (_isLoading) return false;
    return _runOperation('update', () async {
      await _runtime.skillsUpdate(
        skillKey: skillKey,
        enabled: enabled,
        apiKey: apiKey,
        env: env,
      );
      await _reload();
    });
  }

  Future<void> _reload() async {
    _skills =
        GatewaySkillsStatus.fromJson(await _runtime.skillsStatus()).skills;
  }

  Future<bool> _runOperation(
    String operation,
    Future<void> Function() action,
  ) async {
    _isLoading = true;
    _error = null;
    _lastOperation = null;
    notifyListeners();
    try {
      await action();
      _lastOperation = operation;
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
