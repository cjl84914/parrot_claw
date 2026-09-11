import 'package:flutter/foundation.dart';
import 'package:parrot_app/data/model/gateway_cron.dart';
import 'package:parrot_app/data/service/openclaw_runtime.dart';

/// Cron 定时任务的界面状态。
///
/// 直接依赖全局 [OpenClawRuntime] 单例，由 ViewModel 负责参数校验、
/// 结果解析和 loading/error 状态，不再经过额外的 Repository 层。
class CronViewModel extends ChangeNotifier {
  CronViewModel({OpenClawRuntime? runtime})
    : _runtime = runtime ?? OpenClawRuntime.instance;

  final OpenClawRuntime _runtime;
  List<GatewayCronJob> _jobs = const [];
  List<Map<String, dynamic>> _runs = const [];
  bool _isLoading = false;
  String? _error;
  String? _lastOperation;

  List<GatewayCronJob> get jobs => List.unmodifiable(_jobs);
  List<Map<String, dynamic>> get runs => List.unmodifiable(_runs);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get lastOperation => _lastOperation;

  Future<bool> load({bool includeDisabled = true}) async {
    if (_isLoading) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _jobs =
          GatewayCronList.fromJson(
            await _runtime.cronList(includeDisabled: includeDisabled),
          ).jobs;
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> loadRuns(String jobId, {int limit = 200}) async {
    if (_isLoading) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _runs =
          GatewayCronRuns.fromJson(
            await _runtime.cronRuns(id: jobId, limit: limit),
          ).entries;
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> run(String jobId, {bool force = true}) =>
      _mutate('run', () async {
        await _runtime.cronRun(id: jobId, force: force);
      });

  Future<bool> add(Map<String, dynamic> payload) => _mutate('add', () async {
    await _runtime.cronAdd(payload: payload);
    await _reload();
  });

  Future<bool> update(String jobId, Map<String, dynamic> patch) =>
      _mutate('update', () async {
        await _runtime.cronUpdate(id: jobId, patch: patch);
        await _reload();
      });

  Future<bool> remove(String jobId) => _mutate('remove', () async {
    await _runtime.cronRemove(id: jobId);
    _jobs = _jobs
        .where((job) => job.id != jobId.trim())
        .toList(growable: false);
  });

  Future<void> _reload() async {
    _jobs = GatewayCronList.fromJson(await _runtime.cronList()).jobs;
  }

  Future<bool> _mutate(String operation, Future<void> Function() action) async {
    if (_isLoading) return false;
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
