import 'package:flutter/foundation.dart';
import 'package:parrot_app/data/model/gateway_skill.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';

/// Skill 管理的界面状态。
///
/// 状态与操作都由 [GatewayRepository] 持有（它复用全局共享的 OpenClawRuntime
/// 会话），本 ViewModel 只做转发与变更通知，写法与 ConnViewModel 保持一致。
class SkillViewModel extends ChangeNotifier {
  SkillViewModel({required GatewayRepository gatewayRepository})
    : _gatewayRepository = gatewayRepository {
    _gatewayRepository.addListener(_notify);
  }

  final GatewayRepository _gatewayRepository;

  void _notify() {
    notifyListeners();
  }

  List<GatewaySkill> get skills => _gatewayRepository.skills;

  bool get isLoading => _gatewayRepository.skillsLoading;

  String? get error => _gatewayRepository.skillsError;

  String? get lastOperation => _gatewayRepository.lastSkillOperation;

  Future<bool> load() async {
    return await _gatewayRepository.loadSkills();
  }

  Future<bool> install({
    required String name,
    required String installId,
    bool? dangerouslyForceUnsafeInstall,
  }) async {
    return await _gatewayRepository.installSkill(
      name: name,
      installId: installId,
      dangerouslyForceUnsafeInstall: dangerouslyForceUnsafeInstall,
    );
  }

  Future<bool> update({
    required String skillKey,
    bool? enabled,
    String? apiKey,
    Map<String, String>? env,
  }) async {
    return await _gatewayRepository.updateSkill(
      skillKey: skillKey,
      enabled: enabled,
      apiKey: apiKey,
      env: env,
    );
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
