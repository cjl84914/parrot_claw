import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/server_list_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/tts_util.dart';
import 'package:provider/provider.dart';

class IndexScreen extends StatefulWidget {
  final ConnViewModel viewModel;
  final Widget child;

  const IndexScreen({super.key, required this.child, required this.viewModel});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  bool _pairingRoutePushed = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
      // _openPairingPageIfNeeded();
    });
  }

  void _onViewModelChanged() {
    if (!mounted || !widget.viewModel.pairingRequired) return;
    _openPairingPageIfNeeded();
  }

  void _openPairingPageIfNeeded() {
    if (!mounted || _pairingRoutePushed || !widget.viewModel.pairingRequired) {
      return;
    }
    final location = GoRouterState.of(context).matchedLocation;
    if (location == Routes.gatewayPairing) return;
    _pairingRoutePushed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.push(Routes.gatewayPairing).whenComplete(() {
        _pairingRoutePushed = false;
      });
    });
  }


  void _connect() {
    widget.viewModel.connect();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    // ConnViewModel 是全局 Provider。IndexScreen 可能因服务器切换重建，
    // 页面销毁不代表应用需要断开网关连接。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).matchedLocation;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel]),
      builder: (context, child) {
        return Scaffold(
          drawer: Drawer(child: ServerListScreen(viewModel: context.read())),
          onDrawerChanged: (isOpened) {
            if (!isOpened) {
              // 确保在路由切换和焦点恢复逻辑完成后，强制收起键盘
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FocusManager.instance.primaryFocus?.unfocus();
              });
            }
          },
          appBar: AppBar(
            title: Builder(
              builder: (c) {
                if (widget.viewModel.isConnecting) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('连接中...', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  );
                } else if (!widget.viewModel.connected) {
                  return Container(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 14),
                            const SizedBox(width: 8),
                            const Text('已断开连接', style: AppTextStyles.caption),
                            TextButton(
                              onPressed: _connect,
                              child: const Text(
                                '连接',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                } else {
                  return PopupMenuButton<String>(
                    initialValue: widget.viewModel.sessionKey,
                    tooltip: '选择会话',
                    onSelected: (String newValue) {
                      widget.viewModel.switchSession(newValue);
                    },
                    offset: const Offset(0, 36),
                    itemBuilder: (BuildContext context) {
                      return widget.viewModel.sessions.map((session) {
                        return PopupMenuItem<String>(
                          value: session['key'],
                          child: Text(session['key']),
                        );
                      }).toList();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.viewModel.sessionKey ?? '',
                              style: AppTextStyles.appBarTitle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
            actions: [],
          ),
          body: Column(
            children: [
              if (widget.viewModel.disconnectReason != null &&
                  !widget.viewModel.connected)
                Container(
                  margin: const EdgeInsets.only(left: 12, right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.large),
                  ),
                  child: Text(
                    widget.viewModel.disconnectReason!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              Expanded(child: widget.child),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex(currentPath),
            onTap: (index) {
              final routes = [Routes.index, Routes.voice, Routes.about];
              context.go(routes[index]);
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天'),
              BottomNavigationBarItem(
                icon: Icon(Icons.keyboard_voice),
                label: '对话',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        );
      },
    );
  }

  int _currentIndex(String path) {
    if (path.startsWith(Routes.index)) return 0;
    if (path.startsWith(Routes.voice)) return 1;
    if (path.startsWith(Routes.about)) return 2;
    return 0;
  }
}
