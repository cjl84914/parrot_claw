import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
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
  final _live2dController = Live2dController();

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
    final speakerOn = widget.viewModel.settingRepository.isSpeakerOn;
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
    setState(() {
      _isPendding = false;
    });
    await TTSUtil().playBase64(audioBase64);
    if (widget.viewModel.settingRepository.isShowFace) {
      _live2dController.speak('data:audio/wav;base64,$audioBase64');
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

  void _initTalk() {
    ASRUtil().setCallbacks(
      onStateChanged: (RecordState recordState) {
        // if (mounted) {
        //   if (recordState == RecordState.record) {
        //     setState(() {
        //       _isRecording = true;
        //     });
        //   }
        //   if (recordState == RecordState.stop) {
        //     setState(() {
        //       _isRecording = false;
        //     });
        //   }
        // }
      },
      onTextResult: (String text) => _sendMessage(text),
      initCallback: () {
        setState(() {
          _isAsrInited = true;
        });
      },
    );
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
                  ? Live2dScreen(controller: _live2dController)
                  : _simpleTalk(),
          floatingActionButton: Padding(
            padding: EdgeInsets.only(bottom: 0.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isPendding &&
                    widget.viewModel.settingRepository.isShowFace)
                  Center(
                    child: SpinKitThreeBounce(size: 24, color: Colors.white),
                  ),
                SizedBox(height: 24),
                // 按钮组
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildIconButton(
                      icon:
                          widget.viewModel.settingRepository.isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                      label: 'Speaker',
                      color:
                          widget.viewModel.settingRepository.isSpeakerOn
                              ? Colors.tealAccent.shade100
                              : Colors.white,
                      iconColor: AppColors.textSecondary,
                      onTap: () async {
                        widget.viewModel.settingRepository.switchSpeaker();
                        await _configureInitialAudio();
                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                    _buildIconButton(
                      icon: _isRecording ? Icons.mic_off : Icons.mic,
                      label: '',
                      color: _isRecording ? Colors.red : AppColors.primary,
                      iconColor: Colors.white,
                      isLarge: true,
                      onTap: () async {
                        if (_isRecording) {
                          await ASRUtil().stop();
                          _isRecording = false;
                        } else {
                          widget.viewModel.subscribeSessionMessage();
                          await ASRUtil().start();
                          _isRecording = true;
                        }
                        setState(() {});
                      },
                    ),
                    // _buildIconButton(
                    //   icon: Icons.record_voice_over_outlined,
                    //   label: 'Talk',
                    //   color: AppColors.surfaceVariant,
                    //   iconColor: AppColors.textSecondary,
                    //   onTap: () {},
                    // ),
                    _buildIconButton(
                      icon:
                          widget.viewModel.settingRepository.isShowFace
                              ? Icons.face
                              : Icons.face_retouching_off,
                      label: 'Talk',
                      color:
                          widget.viewModel.settingRepository.isShowFace
                              ? Colors.tealAccent.shade100
                              : Colors.white,
                      iconColor: AppColors.textSecondary,
                      onTap: () {
                        widget.viewModel.settingRepository.switchShowFace();
                      },
                    ),
                  ],
                ),
                SizedBox(height: 30.h),
              ],
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
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
        SizedBox(height: 20.h),
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
              '点击麦克风开始',
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

  /// 构建圆形功能按钮
  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    bool isLarge = false,
    required Function() onTap,
  }) {
    double size = isLarge ? 76.r : 60.r;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow:
                  isLarge
                      ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                      : null,
            ),
            child: Icon(icon, size: isLarge ? 36.r : 28.r, color: iconColor),
          ),
          if (label.isNotEmpty) ...[
            SizedBox(height: 8.h),
            // Text(
            //   label,
            //   style: AppTextStyles.caption.copyWith(
            //     color: AppColors.textSecondary,
            //   ),
            // ),
          ],
        ],
      ),
    );
  }
}
