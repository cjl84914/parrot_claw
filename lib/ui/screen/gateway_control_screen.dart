import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/repository/local_gateway_repository.dart';
import 'package:parrot_app/util/result.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:provider/provider.dart';

class GatewayControlScreen extends StatefulWidget {
  const GatewayControlScreen({super.key});

  @override
  State<GatewayControlScreen> createState() => _GatewayControlScreenState();
}

class _GatewayControlScreenState extends State<GatewayControlScreen> {
  LocalGatewayStatus? _status;
  bool _loading = true;
  bool _operating = false;
  String? _error;
  Timer? _refreshTimer;

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_operating) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return const Scaffold(
        body: Center(child: Text('Gateway 控制仅支持桌面版')),
      );
    }

    final connection = context.watch<ConnViewModel>().connected;
    final status = _status;
    final gatewayRunning = status?.gatewayRunning == true;
    final nodeAvailable = status?.nodeAvailable == true;
    final address = status?.address ??
        (status?.port == null ? '--' : '127.0.0.1:${status!.port}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenClaw Gateway'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _loading || _operating ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildOverview(
            connection: connection,
            nodeAvailable: nodeAvailable,
            gatewayRunning: gatewayRunning,
            address: address,
          ),
          const SizedBox(height: 16),
          _buildAction(
            gatewayRunning: gatewayRunning,
            installed: status?.installed == true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _buildError(),
          ],
        ],
      ),
    );
  }

  Widget _buildOverview({
    required bool connection,
    required bool nodeAvailable,
    required bool gatewayRunning,
    required String address,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          children: [
            _buildRow(
              'Connection',
              connection ? 'Connected' : 'Not connected',
              connection,
            ),
            _buildRow(
              'Node',
              nodeAvailable ? 'Online' : 'Offline',
              nodeAvailable,
            ),
            _buildRow(
              'Gateway',
              gatewayRunning ? 'Running' : 'Stopped',
              gatewayRunning,
            ),
            _buildRow('Address', address, gatewayRunning),
            _buildRow(
              'Status',
              _statusLabel,
              gatewayRunning,
              last: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, bool active, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: AppTextStyles.bodyMedium),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.online : AppColors.offline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: active ? null : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction({required bool gatewayRunning, required bool installed}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!installed) {
      return const Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.warning_amber_outlined, color: AppColors.warning),
          title: Text('未检测到 OpenClaw'),
          subtitle: Text('请先完成本机 OpenClaw 安装配置。'),
        ),
      );
    }

    final action = gatewayRunning ? _stop : _start;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _operating ? null : action,
        icon: _operating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(gatewayRunning ? Icons.stop : Icons.play_arrow, color: Colors.white),
        label: Text(gatewayRunning ? '关闭' : '启动', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildError() {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.error.withValues(alpha: 0.1),
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: AppColors.error),
        title: const Text('操作失败'),
        subtitle: Text(_error!),
      ),
    );
  }

  String get _statusLabel {
    if (_loading) return 'Checking';
    if (_status == null || !_status!.installed) return 'Not installed';
    if (_status!.gatewayRunning) return 'Running';
    if (_status!.address == null && _status!.port == null) return 'Stopped';
    return 'Unknown';
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_operating) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final repository = context.read<LocalGatewayRepository>();
    final result = await repository.refresh();
    if (!mounted) return;
    if (result is Ok<LocalGatewayStatus>) {
      setState(() {
        _status = result.value;
        _loading = false;
        _error = null;
      });
    } else if (result is Error<LocalGatewayStatus>) {
      setState(() {
        _loading = false;
        _error = result.error.toString();
      });
    }
  }

  Future<void> _start() => _runOperation(
        context.read<LocalGatewayRepository>().startGateway,
      );

  Future<void> _stop() => _runOperation(
        context.read<LocalGatewayRepository>().stopGateway,
      );

  Future<void> _runOperation(
    Future<dynamic> Function({void Function(String line)? onOutput}) action,
  ) async {
    if (_operating) return;
    setState(() {
      _operating = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      if (result is Error<LocalGatewayStatus>) {
        setState(() => _error = result.error.toString());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _operating = false);
        await _refresh(silent: true);
      }
    }
  }
}
