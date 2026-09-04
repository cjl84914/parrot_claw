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
import 'package:parrot_app/ui/screen/live2d_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/flutter_tts_util.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:parrot_app/util/tts_util.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

class VoiceScreen extends StatefulWidget {
  final ConnViewModel viewModel;

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
      await TTSUtil().setSpeakerOn(speakerOn);
    }
    if (Platform.isIOS) {
      // await _flutterTTSUtil.configureIosAudioSession(speakerOn: speakerOn);
    }
  }

  void _connect() async {
    _pendingRunSubscription = widget.viewModel.pendingRunEvents?.listen((
      lastTextContent,
    ) {
      if (lastTextContent.isNotEmpty) {
        _lastTextContent = lastTextContent;
        if (widget.viewModel.isOpenclawTTS()) {
          widget.viewModel.sendTalkSpeak(
            StringUtil.cleanTextForTts(lastTextContent),
          );
        } else {
          //flutterTTS的iOS和Macos只能输出audio/x-caf格式
          if (Platform.isIOS || Platform.isMacOS) {
            _flutterTTsSpeak(StringUtil.cleanTextForTts(lastTextContent));
          } else {
            _localSpeak(StringUtil.cleanTextForTts(lastTextContent));
          }
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

  Future<void> _localSpeak(String text) async {
    final audioBase64 = await FlutterTTSUtil().getTtsAudioBase64(text);
    _speak(audioBase64);
  }

  Future<void> _flutterTTsSpeak(String text) async {
    FlutterTTSUtil().setCallbacks(
      onComplete: () async {
        print('flutter tts complete');
        await _configureInitialAudio();
        await ASRUtil().resume(); //恢复ASR
      },
    );
    //不是打断模式，暂停ASR
    if (!widget.viewModel.settingRepository.isTTSAbort) {
      await ASRUtil().pause();
    }
    setState(() {
      _isPendding = false;
    });
    FlutterTTSUtil().speak(text);
  }

  Future<void> _speak(String audioBase64) async {
    TTSUtil().setCallbacks(
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
      await TTSUtil().playBase64(audioBase64);
      if (widget.viewModel.settingRepository.isShowFace) {
        _live2dController.speak('data:audio/wav;base64,$audioBase64');
      }
    }
  }

  Future<void> _speakUrl(String audioUrl) async {
    TTSUtil().setCallbacks(
      onComplete: () async {
        await _configureInitialAudio();
        await ASRUtil().resume(); //恢复ASR
      },
    );
    //不是打断模式，暂停ASR
    if (!widget.viewModel.settingRepository.isTTSAbort) {
      await ASRUtil().pause();
    }
    setState(() {
      _isPendding = false;
    });
    await TTSUtil().playUrl(audioUrl);
    if (widget.viewModel.settingRepository.isShowFace) {
      _live2dController.speak(audioUrl);
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
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
                        }

                        context.go(Routes.index);

                        // else {
                        //   widget.viewModel.subscribeSessionMessage();
                        //   // 按实际启动结果更新状态，失败时给出原因提示
                        //   _isRecording = await ASRUtil().start();
                        //   if (!_isRecording && context.mounted) {
                        //     ScaffoldMessenger.of(context).showSnackBar(
                        //       const SnackBar(
                        //         content: Text('录音启动失败，请检查麦克风权限/设备'),
                        //       ),
                        //     );
                        //   }
                        // }
                        //
                        // if (mounted) {
                        //   setState(() {});
                        // }
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
            left: 20.w,
            right: 20.w,
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
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
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
            fontSize: 16.sp,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
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
            fontSize: 18.sp,
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
                fontSize: 14.sp,
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
