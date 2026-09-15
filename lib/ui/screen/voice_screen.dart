import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/screen/live2d_screen.dart';
import 'package:parrot_app/ui/view_model/chat_viewmodel.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

class VoiceScreen extends StatefulWidget {
  final ChatViewModel viewModel;

  const VoiceScreen({super.key, required this.viewModel});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  StreamSubscription? _eventSubscription;
  StreamSubscription? _eventVoiceSubscription;
  StreamSubscription? _pendingRunSubscription;
  StreamSubscription? _sessionMessageSub;

  bool _isAsrInited = false;
  bool _isRecording = false;
  bool _isPendding = false;
  bool _isShowSubtitle = true;
  final _live2dController = Live2dController();
  String _lastTextContent = '';

  @override
  void initState() {
    super.initState();
    _init();
    _configureInitialAudio();
  }

  void _init() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
      _initTalk();
    });
  }

  Future<void> _configureInitialAudio() async {
    // audio_session 仅支持 Android/iOS/macOS/Web，
    // Windows/Linux 无插件实现，调用会抛 MissingPluginException，直接跳过。
    if (Platform.isWindows || Platform.isLinux) {
      return;
    }

    final speakerOn = widget.viewModel.settingRepository.isSpeakerOn;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              speakerOn
                  ? AVAudioSessionCategoryOptions.allowBluetooth |
                      AVAudioSessionCategoryOptions.defaultToSpeaker |
                      AVAudioSessionCategoryOptions.mixWithOthers
                  : AVAudioSessionCategoryOptions.allowBluetooth |
                      AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            usage: AndroidAudioUsage.voiceCommunication,
            contentType: AndroidAudioContentType.speech,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransient, // 初始时允许获取焦点
        ),
      );
      await session.setActive(true);
    } catch (e) {
      // 个别平台/设备配置音频会话失败不应阻断语音功能，仅记录日志
      debugPrint('configure audio session failed: $e');
    }

    if (Platform.isAndroid) {
      await EdgeTTSUtil().setSpeakerOn(speakerOn);
    }
    if (Platform.isIOS) {
    }
  }

  void _connect() async {
    _pendingRunSubscription = widget.viewModel.pendingRunEvents?.listen((
      lastTextContent,
    ) async {
      if (lastTextContent.isNotEmpty) {
        _lastTextContent = lastTextContent;
        final text = StringUtil.cleanTextForTts(lastTextContent);
        if (widget.viewModel.isOpenclawTTS()) {
          // 网关侧 TTS：音频由 voiceEvents 回推，这里只发文本。
          widget.viewModel.sendTalkSpeak(text);
        } else {
          // 本地 TTS 统一走 Edge 在线合成。
          // 原实现按平台分流（iOS/macOS/Windows 用 flutter_tts、其余用 sherpa），
          // 是因为 flutter_tts 在 iOS/macOS 只能输出 caf；Edge 全平台统一输出
          // PCM/WAV，分流已无必要。
          await _edgeSpeak(text);
        }
      }
    });

    _eventVoiceSubscription = widget.viewModel.voiceEvents?.listen((
      voiceData,
    ) async {
      await _speak(voiceData);
    });

    // _sessionMessageSub = widget.viewModel.sessionMessageStream.listen((sessionMessage) {
    //   final text = sessionMessage.text;
    //   for (final audio in sessionMessage.audioAttachments) {
    //     final audioPath = audio.url;
    //     print(widget.viewModel.buildMediaUrl(audioPath!));
    //     _speakUrl(widget.viewModel.buildMediaUrl(audioPath));
    //   }
    // });
  }

  /// 本地 TTS：Edge 在线合成成 PCM/WAV → 播放 → 喂数字人口型。
  Future<void> _edgeSpeak(String text) async {
    try {
      final audioBase64 = await EdgeTTSUtil().getTtsAudioBase64(text);
      await _speak(audioBase64);
    } on Object catch (error) {
      // 合成失败（断网、服务端变更）不该把页面打挂，提示由 EdgeTTSUtil 负责弹。
      debugPrint('Edge TTS 合成失败: $error');
    }
  }

  Future<void> _speak(String audioBase64) async {
    EdgeTTSUtil().setCallbacks(
      onComplete: () async {
        await _configureInitialAudio();
        await ASRUtil().resume(); //恢复ASR
      },
    );
    //不是打断模式，暂停ASR
    if (!widget.viewModel.settingRepository.isTTSAbort) {
      await ASRUtil().pause();
    }
    if (mounted) {
      setState(() {
        _isPendding = false;
      });
      await EdgeTTSUtil().playBase64(audioBase64);
      if (widget.viewModel.settingRepository.isShowFace) {
        // Edge 给的是 mp3，而 Live2D 的 _wavFileHandler 只认 RIFF/WAVE，
        // 所以走转码路径：WebView 里用 Web Audio 解码成 PCM 再拼 WAV。
        _live2dController.speakEncodedAudio(
          'data:${EdgeTTSUtil().audioMimeType};base64,$audioBase64',
        );
      }
    }
  }

  void _initTalk() async {
    ASRUtil().setCallbacks(
      onStateChanged: (RecordState recordState) {
        if (mounted) {
          if (recordState == RecordState.record) {
            setState(() {
              _isRecording = true;
            });
          }
          if (recordState == RecordState.stop) {
            setState(() {
              _isRecording = false;
            });
          }
        }
      },
      onTextResult: (String text) => _sendMessage(text),
      onError: (String error) {
        if (mounted) {
          MySnackBar.showError(context, error);
        }
      },
      initCallback: () async {
        setState(() {
          _isAsrInited = true;
        });
      },
    );
    ASRUtil().start();
  }

  @override
  void dispose() {
    widget.viewModel.unsubscribeSessionMessage();
    ASRUtil().stop();
    // 离开页面时停掉正在播/正在合成的语音（EdgeTTSUtil 是全局单例，不在这里 dispose）。
    unawaited(EdgeTTSUtil().stop());
    _eventSubscription?.cancel();
    _pendingRunSubscription?.cancel();
    _eventVoiceSubscription?.cancel();
    _sessionMessageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.read<SettingRepository>(),
      builder: (context, child) {
        return Scaffold(
          body:
              widget.viewModel.settingRepository.isShowFace
                  ? _faceTalk()
                  : _simpleTalk(),
          floatingActionButton: Padding(
            padding: EdgeInsets.only(bottom: 0.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 按钮组
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 扬声器开关
                    _buildIconButton(
                      icon:
                          widget.viewModel.settingRepository.isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                      color: Colors.white,
                      iconColor: AppColors.textSecondary,
                      onTap: () async {
                        widget.viewModel.settingRepository.switchSpeaker();
                        await _configureInitialAudio();

                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),

                    // 字幕开关
                    _buildIconButton(
                      icon:
                          _isShowSubtitle
                              ? Icons.subtitles
                              : Icons.subtitles_off,
                      color: Colors.white,
                      iconColor: AppColors.textSecondary,
                      onTap: () {
                        setState(() {
                          _isShowSubtitle = !_isShowSubtitle;
                        });
                      },
                    ),

                    // 数字人开关
                    _buildIconButton(
                      icon:
                          widget.viewModel.settingRepository.isShowFace
                              ? Icons.face
                              : Icons.face_retouching_off,
                      color: Colors.white,
                      iconColor: AppColors.textSecondary,
                      onTap: () {
                        widget.viewModel.settingRepository.switchShowFace();
                      },
                    ),

                    _buildIconButton(
                      icon: _isRecording ? Icons.mic : Icons.mic_off,
                      color: _isRecording ? Colors.red : Colors.white,
                      iconColor:
                          _isRecording ? Colors.white : AppColors.textSecondary,
                      onTap: () async {
                        // _sendMessage('测试');
                        if (_isRecording) {
                          await ASRUtil().stop();
                          _isRecording = false;
                          if (kIsMobile) {
                            context.go(Routes.index);
                          }
                        } else {
                          await ASRUtil().start();
                          _isRecording = true;
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
              ],
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }

  Widget _faceTalk() {
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Live2dScreen(controller: _live2dController),
        // 字幕区域：位于屏幕中部和底部按钮上方
        if (_isShowSubtitle)
          Positioned(
            left: 20,
            right: 20,
            top: screenHeight * 0.4,
            bottom: 110.h,
            child: _buildSubtitle(),
          ),
        if (_isPendding) SpinKitThreeBounce(size: 24, color: Colors.white),
      ],
    );
  }

  Widget _buildSubtitle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.48),
            Colors.black.withOpacity(0.0),
          ],
        ),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          _lastTextContent,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  void _sendMessage(String? text) async {
    if (text == null || text.trim().isEmpty) return;
    if (mounted) {
      setState(() {
        _isPendding = true;
      });
    }
    _abortMessage();
    try {
      await widget.viewModel.sendChatMessage(text);
    } catch (e) {
      MySnackBar.showError(context, e.toString());
    }
  }

  void _abortMessage() async {
    widget.viewModel.abortMessage();
  }

  Widget _simpleTalk() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.mic, size: 80.r, color: AppColors.textTertiary),
        SizedBox(height: 12.h),
        Text(
          '对话模式',
          style: AppTextStyles.titleLarge.copyWith(
            fontSize: 18,
            color: AppColors.textSecondary,
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              '',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required Function() onTap,
  }) {
    const buttonSize = 60.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: buttonSize.r,
        height: buttonSize.r,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 28.r, color: iconColor),
      ),
    );
  }
}
