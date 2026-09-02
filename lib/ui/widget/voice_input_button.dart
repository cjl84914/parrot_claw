import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class VoiceInputButton extends StatefulWidget {
  final Function() startRecording;
  final Function() stopRecording;

  const VoiceInputButton({
    super.key,
    required this.startRecording,
    required this.stopRecording,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  // 语音输入相关
  bool _isRecording = false;
  bool _isCancelling = false;
  double _startDragY = 0.0;
  final double _cancelThreshold = 50.0;
  Timer? _waveAnimationTimer;
  final List<double> _waveHeights = List.filled(20, 0.0);
  final Random _random = Random();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) {
        setState(() {
          _isRecording = true;
          _isCancelling = false;
          _startDragY = details.globalPosition.dy;
        });
        widget.startRecording();
        _startWaveAnimation();
      },
      onLongPressMoveUpdate: (details) {
        // 计算垂直移动距离
        final double dragDistance = _startDragY - details.globalPosition.dy;

        // 如果上滑超过阈值，标记为取消状态
        if (dragDistance > _cancelThreshold && !_isCancelling) {
          setState(() {
            _isCancelling = true;
          });
          // 震动反馈
          HapticFeedback.mediumImpact();
        } else if (dragDistance <= _cancelThreshold && _isCancelling) {
          setState(() {
            _isCancelling = false;
          });
          // 震动反馈
          HapticFeedback.lightImpact();
        }
      },
      onLongPressEnd: (details) {
        final wasRecording = _isRecording;
        final wasCancelling = _isCancelling;

        setState(() {
          _isRecording = false;
        });

        _stopWaveAnimation();

        if (wasRecording) {
          if (wasCancelling) {
            _cancelRecording();
          } else {
            widget.stopRecording();
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: ChatTheme.dark().colors.surface,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 波纹动画效果
            if (_isRecording && !_isCancelling) _buildWaveAnimationIndicator(),
            // 文字提示
            Center(
              child: Text(
                _isRecording
                    ? _isCancelling
                        ? '松开手指，取消发送'
                        : '松开发送，上滑取消'
                    : '按住说话',
                style: TextStyle(
                  color:
                      _isRecording
                          ? _isCancelling
                              ? Colors.red
                              : Colors.blue.shade700
                          : Colors.white,
                  fontSize: 16,
                  fontWeight:
                      _isRecording ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 启动波形动画
  void _startWaveAnimation() {
    _waveAnimationTimer?.cancel();
    _waveAnimationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (_isRecording && !_isCancelling) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            _waveHeights[i] = 0.5 + _random.nextDouble() * 0.5;
          }
        });
      }
    });
  }

  // 停止波形动画
  void _stopWaveAnimation() {
    _waveAnimationTimer?.cancel();
    _waveAnimationTimer = null;
  }

  // 取消录音
  void _cancelRecording() async {
    EasyLoading.showToast('取消发送');
    widget.stopRecording();
  }

  // 构建波形动画指示器
  Widget _buildWaveAnimationIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          16,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 20 * _waveHeights[index],
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(1.5),
            ),
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }
}
