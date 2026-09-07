import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:parrot_app/config/app_theme.dart';

/// 全局顶部通知工具类
/// 使用Overlay实现真正的顶部显示
class MySnackBar {
  static OverlayEntry? _currentOverlay;

  /// 显示成功消息（AppBar下方）
  static void showSuccess(BuildContext context, String message) {
    _showTopMessage(
      context,
      message,
      AppColors.online,
      Icon(Icons.info, color: AppColors.online.withOpacity(0.5), size: 20),
    );
  }

  /// 显示错误消息（AppBar下方）
  static void showError(BuildContext context, String message) {
    _showTopMessage(
      context,
      message,
      AppColors.error,
      Icon(Icons.error, color: AppColors.error.withOpacity(0.5), size: 20),
    );
  }

  /// 显示警告消息（AppBar下方）
  static void showWarning(BuildContext context, String message) {
    _showTopMessage(
      context,
      message,
      AppColors.warning,
      Icon(Icons.warning, color: AppColors.warning.withOpacity(0.5), size: 20),
    );
  }

  /// 显示信息消息（AppBar下方）
  static void showInfo(BuildContext context, String message) {
    _showTopMessage(
      context,
      message,
      AppColors.primary,
      Icon(Icons.error, color: AppColors.primary.withOpacity(0.5), size: 20),
    );
  }

  /// 显示普通消息（AppBar下方）
  static void show(BuildContext context, String message) {
    _showTopMessage(
      context,
      message,
      AppColors.primary,
      Icon(Icons.info, color: AppColors.primary.withOpacity(0.5), size: 20),
    );
  }

  /// 内部方法：使用Overlay显示顶部消息
  static void _showTopMessage(
    BuildContext context,
    String message,
    Color backgroundColor,
    Widget icon,
  ) {
    // 移除之前的通知
    _removeCurrentOverlay();

    final MediaQueryData mediaQuery = MediaQuery.of(context);
    double statusBarHeight = mediaQuery.padding.top;
    // final double appBarHeight = kToolbarHeight;
    if (statusBarHeight == 0.0) {
      statusBarHeight = 36;
    }
    final double topPosition = kIsWeb ? 16 : 14 + statusBarHeight;

    _currentOverlay = OverlayEntry(
      builder:
          (context) => _TopMessageWidget(
            message: message,
            backgroundColor: backgroundColor,
            icon: icon,
            topPosition: topPosition,
            onDismiss: _removeCurrentOverlay,
          ),
    );

    Overlay.of(context).insert(_currentOverlay!);

    // 3秒后自动消失
    Future.delayed(const Duration(seconds: 3), () {
      _removeCurrentOverlay();
    });
  }

  /// 移除当前的Overlay
  static void _removeCurrentOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

/// 顶部消息组件
class _TopMessageWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Widget icon;
  final double topPosition;
  final VoidCallback onDismiss;

  const _TopMessageWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.topPosition,
    required this.onDismiss,
  });

  @override
  State<_TopMessageWidget> createState() => _TopMessageWidgetState();
}

class _TopMessageWidgetState extends State<_TopMessageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: -100, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topPosition,
      left: 8,
      right: 8,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(minHeight: 44.0),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFFFFF).withOpacity(0.07),
                          Color(0xFFFFFFFF).withOpacity(0.6).withOpacity(0.07),
                        ],
                        stops: [0.0, 1.0],
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: ShapeDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            widget.backgroundColor
                                .withOpacity(0.75)
                                .withOpacity(0.15),
                            widget.backgroundColor.withOpacity(0.0),
                          ],
                          stops: [0.0, 0.23],
                        ),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 1,
                            color: const Color(0x14FFEEF5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        shadows: [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 20,
                            offset: Offset(0, 0),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          widget.icon,
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                color: const Color(
                                  0xFFD6DDE4,
                                ) /* dark-text-text-primary */,
                                fontSize: 14,
                                fontFamily: 'Helvetica Neue',
                                fontWeight: FontWeight.w500,
                                height: 1.20,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              _animationController.reverse().then((_) {
                                widget.onDismiss();
                              });
                            },
                            child: const Icon(
                              Icons.close,
                              color: Color(0xFFB8C5D6),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
