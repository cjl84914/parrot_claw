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

  // ==================== ClawHub 搜索 / 安装审核 ====================
  //
  // 与 Skill 列表是两套状态：ClawHub 搜索只查远端目录，不改变本地已装列表。

  /// 最近一次 ClawHub 搜索的结果。
  List<GatewayClawHubSkillSummary> get clawHubResults =>
      _gatewayRepository.clawHubResults;

  /// 最近一次搜索用的关键字。
  String get clawHubQuery => _gatewayRepository.clawHubQuery;

  /// 是否正在搜索 ClawHub。
  bool get clawHubSearching => _gatewayRepository.clawHubSearching;

  /// 最近一次搜索或审核失败的原因。
  String? get clawHubError => _gatewayRepository.clawHubError;

  /// 搜索成功但无结果时的提示。
  String? get clawHubMessage => _gatewayRepository.clawHubMessage;

  /// 正在读取详情的技能引用（用于该行的 loading 态）。
  String? get clawHubReviewingSlug =>
      _gatewayRepository.clawHubReviewingSlug;

  /// 已加载的安装审核信息，null 表示没有待确认的安装。
  GatewayClawHubInstallReview? get clawHubInstallReview =>
      _gatewayRepository.clawHubInstallReview;

  /// 网关是否支持 ClawHub 搜索与安装（hello 是否宣告了完整方法族）。
  bool get clawHubSkillsAvailable =>
      _gatewayRepository.clawHubSkillsAvailable;

  /// 当前连接是否拿到 `operator.admin`（安装 ClawHub 技能需要）。
  bool get clawHubCanInstall => _gatewayRepository.clawHubCanInstall;

  /// 正在安装的 ClawHub 引用。
  Set<String> get clawHubInstallingSlugs =>
      _gatewayRepository.clawHubInstallingSlugs;

  /// 搜索 ClawHub 技能。
  Future<bool> searchClawHubSkills(String query) async {
    return await _gatewayRepository.searchClawHubSkillsFromGateway(query);
  }

  /// 读取安装前的版本审核信息。
  Future<bool> reviewClawHubSkillInstall(
    GatewayClawHubSkillSummary skill,
  ) async {
    return await _gatewayRepository.reviewClawHubSkillInstallFromGateway(skill);
  }

  /// 安装审核确认过的 ClawHub 技能，成功后自动刷新 Skill 列表。
  Future<bool> installClawHubSkill({
    required String slug,
    String? version,
  }) async {
    return await _gatewayRepository.installClawHubSkillFromGateway(
      slug: slug,
      version: version,
    );
  }

  /// 关掉待确认的安装（弹窗「取消」）。
  void dismissClawHubSkillInstallReview() {
    _gatewayRepository.dismissClawHubSkillInstallReview();
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
