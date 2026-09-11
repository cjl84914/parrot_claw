import 'package:flutter/foundation.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/data/repository/gateway_repository.dart';

/// Cron 定时任务的界面状态。
///
/// 状态与操作都由 [GatewayRepository] 持有（它复用全局共享的 OpenClawRuntime
/// 会话），本 ViewModel 只做转发与变更通知，写法与 ConnViewModel 保持一致。
class CronViewModel extends ChangeNotifier {
  CronViewModel({required GatewayRepository gatewayRepository})
    : _gatewayRepository = gatewayRepository {
    _gatewayRepository.addListener(_notify);
  }

  final GatewayRepository _gatewayRepository;

  void _notify() {
    notifyListeners();
  }

  List<GatewayCronJob> get jobs => _gatewayRepository.cronJobs;

  List<Map<String, dynamic>> get runs => _gatewayRepository.cronRuns;

  bool get isLoading => _gatewayRepository.cronLoading;

  String? get error => _gatewayRepository.cronError;

  String? get lastOperation => _gatewayRepository.lastCronOperation;

  Future<bool> load({bool includeDisabled = true}) async {
    return await _gatewayRepository.loadCronJobs(
      includeDisabled: includeDisabled,
    );
  }

  Future<bool> loadRuns(String jobId, {int limit = 200}) async {
    return await _gatewayRepository.loadCronRuns(jobId, limit: limit);
  }

  Future<bool> run(String jobId, {bool force = true}) async {
    return await _gatewayRepository.runCronJob(jobId, force: force);
  }

  Future<bool> add(Map<String, dynamic> payload) async {
    return await _gatewayRepository.addCronJob(payload);
  }

  Future<bool> update(String jobId, Map<String, dynamic> patch) async {
    return await _gatewayRepository.updateCronJob(jobId, patch);
  }

  Future<bool> remove(String jobId) async {
    return await _gatewayRepository.removeCronJob(jobId);
  }

  @override
  void dispose() {
    // GatewayRepository 由根级 Provider 持有，本 ViewModel 只是消费者，
    // 不能在这里 dispose，否则会连带拆掉共享连接。
    _gatewayRepository.removeListener(_notify);
    super.dispose();
  }
}
