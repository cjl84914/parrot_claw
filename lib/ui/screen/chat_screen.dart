import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_file_message/flyer_chat_file_message.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:parrot_app/config/app_theme.dart';
import 'package:parrot_app/data/model/message.dart' hide ChatMessage;
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/view_model/conn_viewmodel.dart';
import 'package:parrot_app/ui/view_model/hive_chat_controller.dart';
import 'package:parrot_app/ui/widget/composer_action_bar.dart';
import 'package:parrot_app/ui/widget/voice_input_button.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/flutter_tts_util.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:parrot_app/data/model/message.dart' as model;

enum InputMode { Text, Voice }

class ChatScreen extends StatefulWidget {
  final ConnViewModel viewModel;

  const ChatScreen({super.key, required this.viewModel});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late final HiveChatController _chatController = HiveChatController();
  final _uuid = const Uuid();
  final _currentUser = const User(
    id: 'me',
    // imageSource: 'https://picsum.photos/id/65/200/200',
    name: 'Me',
  );
  final _recipient = const User(
    id: 'assistant',
    // imageSource: 'https://picsum.photos/id/265/200/200',
    name: 'Parrot',
  );
  final _systemUser = const User(id: 'system');
  StreamSubscription? _eventSubscription;
  StreamSubscription? _eventSessionUpdateSubscription;
  StreamSubscription? _pendingRunSubscription;

  InputMode _inputMode = InputMode.Text;

  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 60;

  final _textEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textEditingController.addListener(() {
      _updateComposerHeight();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
      _initTalk();
    });
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
      // 录音/初始化失败不再静默：直接在聊天页提示原因（如 Windows 麦克风权限）
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
      initCallback: () {
        // setState(() {
        //   _isAsrInited = true;
        // });
      },
    );
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _pendingRunSubscription?.cancel();
    _eventSessionUpdateSubscription?.cancel();
    _chatController.dispose();
    ASRUtil().stop();
    super.dispose();
  }

  void _updateComposerHeight() async {
    final context = _composerKey.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    await Future.delayed(Duration(seconds: 1));
    final height = renderBox.size.height;
    if (height != _composerHeight) {
      setState(() {
        _composerHeight = height - 48;
      });
    }
  }

  Message _toUiMessage(model.ChatMessage m) {
    String authorId = m.role; // 直接映射 role: user, assistant, system
    if (authorId == 'user') authorId = 'me';

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      m.timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );

    // 寻找媒体内容（支持 base64）
    final mediaContent =
        m.content.isEmpty ? ChatMessageContent() : m.content.first;
    final contentType = mediaContent.type;
    // 寻找文本内容
    final textContent = m.content
        .where((c) => c.type == 'text')
        .map((c) => c.text ?? '')
        .join('\n');

    if (contentType == 'text') {
      if (m.role == 'assistant') {
        return TextMessage(
          id: m.id,
          authorId: authorId,
          text: textContent,
          createdAt: createdAt,
          status: MessageStatus.seen,
        );
      } else if (m.role == 'user') {
        return TextMessage(
          id: m.id,
          authorId: authorId,
          text: textContent,
          createdAt: createdAt,
          status: MessageStatus.seen,
        );
      }
      // else if (m.role == 'toolResult') {
      //   return TextMessage(
      //     id: m.id,
      //     authorId: authorId,
      //     text: 'Tool Output:$textContent',
      //   );
      // }
    } else if (contentType == 'toolCall') {
      return TextMessage(id: m.id, authorId: authorId, text: 'Tool Call');
    } else if (contentType == 'image') {
      if (mediaContent.text != null) {
        return ImageMessage(
          id: m.id,
          authorId: authorId,
          size: 0,
          createdAt: createdAt,
          source: mediaContent.text!,
        );
      }
    } else if (contentType == 'file' ||
        contentType == 'video' ||
        contentType == 'audio') {
      if (mediaContent.text != null) {
        return FileMessage(
          id: m.id,
          authorId: authorId,
          size: 0,
          createdAt: createdAt,
          source: mediaContent.text!,
          name: mediaContent.fileName ?? 'file',
        );
      }
    }

    return TextMessage(id: m.id, authorId: authorId, text: '未知内容');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, child) {
        if (widget.viewModel.isHistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '打开侧边栏',
              onPressed: () => indexScaffoldKey.currentState?.openDrawer(),
            ),
            centerTitle: false,
            title: const Text('ParrotClaw'),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => context.go(Routes.voice),
                  icon: const Icon(Icons.phone_outlined, size: 24),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Chat(
                // key: ValueKey(widget.server.id),
                backgroundColor: Colors.transparent,
                builders: Builders(
                  emptyChatListBuilder: (c) {
                    return const Center(child: Text("没有数据呢～"));
                  },
                  chatAnimatedListBuilder: (context, itemBuilder) {
                    return ChatAnimatedList(
                      itemBuilder: itemBuilder,
                      // initialScrollToEndMode: InitialScrollToEndMode.none,
                      insertAnimationDurationResolver: (message) {
                        if (message is SystemMessage) {
                          return Duration.zero;
                        }
                        return null;
                      },
                    );
                  },
                  customMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.brightness == Brightness.dark
                                  ? ChatColors.dark().surfaceContainer
                                  : ChatColors.light().surfaceContainer,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                        ),
                        child: IsTypingIndicator(),
                      ),
                  imageMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => GestureDetector(
                        onTap: () {
                          launchUrl(Uri.parse(message.source));
                        },
                        child: FlyerChatImageMessage(
                          message: message,
                          index: index,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return Text(error.toString());
                          },
                        ),
                      ),
                  // audioMessageBuilder:
                  //     (
                  //     context,
                  //     message,
                  //     index, {
                  //   required bool isSentByMe,
                  //   MessageGroupStatus? groupStatus,
                  // }) => FlyerChatAudioMessage(
                  //   message: message,
                  //   index: index,
                  // ),
                  // videoMessageBuilder: (
                  //   context,
                  //   message,
                  //   index, {
                  //   required bool isSentByMe,
                  //   MessageGroupStatus? groupStatus,
                  // }) {
                  //   return VideoMessageWidget(url: message.source);
                  // },
                  systemMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => FlyerChatSystemMessage(
                        message: message,
                        index: index,
                      ),
                  composerBuilder:
                      (context) => Composer(
                        key: _composerKey,
                        textEditingController: _textEditingController,
                        padding: EdgeInsets.only(top: 8, bottom: 4, right: 48),
                        backgroundColor: ChatColors.dark().surface,
                        topWidget: ComposerActionBar(
                          buttons: [
                            ComposerActionButton(
                              visible: true,
                              icon: Icons.delete_sweep,
                              title: 'Clear',
                              onPressed: () {
                                _chatController.setMessages([]);
                                widget.viewModel.sendChatMessage('/reset');
                              },
                            ),
                            ComposerActionButton(
                              visible: true,
                              icon: Icons.stop_circle_rounded,
                              title: 'Abort ',
                              onPressed: () => _abortMessage(),
                              color:
                                  widget.viewModel.runId != ''
                                      ? AppColors.secondary
                                      : Colors.grey,
                            ),
                            ComposerActionButton(
                              visible: true,
                              icon: Icons.psychology_outlined,
                              title: widget.viewModel.model!,
                              onPressed: () => _showModelOptions(context),
                              color: Colors.grey,
                            ),
                            ComposerActionButton(
                              visible: true,
                              icon: Icons.lightbulb_outline,
                              title: widget.viewModel.thinkingDefault,
                              onPressed: () => _showThinkOptions(context),
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        sendOnEnter: true,
                        // sendButtonHidden: true,
                      ),
                  // linkPreviewBuilder: (context, message, isSentByMe) {
                  //   // It's up to you to (optionally) implement the logic to avoid every
                  //   // message to refetch the preview data
                  //   //
                  //   // For example, you can use a metadata to indicate if the preview
                  //   // was already fetched (or null).
                  //   //
                  //   // Additionally, you can cache the data to avoid re-fetching across app restarts.
                  //   return LinkPreview(
                  //     text: message.text,
                  //     linkPreviewData: message.linkPreviewData,
                  //     onLinkPreviewDataFetched: (linkPreviewData) {
                  //       _chatController.updateMessage(
                  //         message,
                  //         message.copyWith(linkPreviewData: linkPreviewData),
                  //       );
                  //     },
                  //     // parentContent: message.text,
                  //   );
                  // },
                  textMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => FlyerChatTextMessage(
                        message: message,
                        index: index,
                        showStatus: false,
                        sentBackgroundColor: AppColors.primary,
                      ),
                  fileMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => GestureDetector(
                        onTap: () {
                          launchUrl(Uri.parse(message.source));
                        },
                        child: FlyerChatFileMessage(
                          message: message,
                          index: index,
                        ),
                      ),
                  chatMessageBuilder: (
                    context,
                    message,
                    index,
                    animation,
                    child, {
                    bool? isRemoved,
                    required bool isSentByMe,
                    MessageGroupStatus? groupStatus,
                  }) {
                    final isSystemMessage = message.authorId == 'system';
                    final isFirstInGroup = groupStatus?.isFirst ?? true;
                    final isLastInGroup = groupStatus?.isLast ?? true;
                    final shouldShowAvatar =
                        !isSystemMessage && isLastInGroup && isRemoved != true;
                    final isCurrentUser = message.authorId == _currentUser.id;
                    final shouldShowUsername =
                        !isSystemMessage && isFirstInGroup && isRemoved != true;

                    Widget? avatar;
                    if (shouldShowAvatar) {
                      avatar = Padding(
                        padding: EdgeInsets.only(
                          left: isCurrentUser ? 8 : 0,
                          right: isCurrentUser ? 0 : 8,
                        ),
                        child: Avatar(userId: message.authorId),
                      );
                    } else if (!isSystemMessage) {
                      avatar = const SizedBox(width: 40);
                    }

                    return ChatMessage(
                      message: message,
                      index: index,
                      animation: animation,
                      isRemoved: isRemoved,
                      groupStatus: groupStatus,
                      topWidget:
                          shouldShowUsername
                              ? Padding(
                                padding: EdgeInsets.only(
                                  bottom: 4,
                                  left: isCurrentUser ? 0 : 48,
                                  right: isCurrentUser ? 48 : 0,
                                ),
                                child: Username(userId: message.authorId),
                              )
                              : null,
                      leadingWidget:
                          !isCurrentUser
                              ? avatar
                              : isSystemMessage
                              ? null
                              : const SizedBox(width: 40),
                      trailingWidget:
                          isCurrentUser
                              ? avatar
                              : isSystemMessage
                              ? null
                              : const SizedBox(width: 40),
                      receivedMessageScaleAnimationAlignment:
                          (message is SystemMessage)
                              ? Alignment.center
                              : Alignment.centerLeft,
                      receivedMessageAlignment:
                          (message is SystemMessage)
                              ? AlignmentDirectional.center
                              : AlignmentDirectional.centerStart,
                      horizontalPadding: (message is SystemMessage) ? 0 : 8,
                      child: child,
                    );
                  },
                ),
                chatController: _chatController,
                currentUserId: _currentUser.id,
                decoration: BoxDecoration(
                  color:
                      theme.brightness == Brightness.dark
                          ? ChatColors.dark().surface
                          : ChatColors.light().surface,
                  // image: DecorationImage(
                  //   image: AssetImage('assets/pattern.png'),
                  //   repeat: ImageRepeat.repeat,
                  //   colorFilter: ColorFilter.mode(
                  //     theme.brightness == Brightness.dark
                  //         ? ChatColors.dark().surfaceContainerLow
                  //         : ChatColors.light().surfaceContainerLow,
                  //     BlendMode.srcIn,
                  //   ),
                  // ),
                ),
                onAttachmentTap: _handleAttachmentTap,
                onMessageLongPress: _handleMessageLongPress,
                onMessageSend: _sendMessage,
                resolveUser:
                    (id) => Future.value(switch (id) {
                      'me' => _currentUser,
                      'recipient' => _recipient,
                      'system' => _systemUser,
                      _ => null,
                    }),
                theme:
                    theme.brightness == Brightness.dark
                        ? ChatTheme.dark()
                        : ChatTheme.light(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 12,
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  height: _composerHeight,
                  padding: EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: Visibility(
                          visible: _inputMode == InputMode.Voice,
                          child: VoiceInputButton(
                            startRecording: () {
                              print("startRecording");
                              ASRUtil().start();
                            },
                            stopRecording: () {
                              print("stopRecording");
                              ASRUtil().stop();
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        alignment: Alignment.center,
                        onPressed: () async {
                          if (_inputMode == InputMode.Voice) {
                            _inputMode = InputMode.Text;
                          } else if (_inputMode == InputMode.Text) {
                            _inputMode = InputMode.Voice;
                          }
                          setState(() {});
                        },
                        icon: Icon(
                          _inputMode == InputMode.Voice
                              ? Icons.keyboard_alt_outlined
                              : Icons.mic_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleMessageLongPress(
    BuildContext context,
    Message message, {
    required int index,
    required LongPressStartDetails details,
  }) async {
    // Skip showing menu for system messages
    if (message.authorId == 'system') return;

    // Calculate position for the menu
    final position = details.globalPosition;

    // Create a Rect for the menu position (small area around tap point)
    final menuRect = Rect.fromCenter(
      center: position,
      width: 0, // Width and height of 0 means show exactly at the point
      height: 0,
    );

    final items = [
      if (message is TextMessage)
        PullDownMenuItem(
          title: '复制',
          icon: CupertinoIcons.doc_on_doc,
          onTap: () {
            _copyMessage(message);
          },
        ),
      if (message is TextMessage)
        PullDownMenuItem(
          title: '朗读',
          icon: CupertinoIcons.speaker_2,
          onTap: () {
            FlutterTTSUtil().speak(StringUtil.cleanTextForTts(message.text));
          },
        ),
      // PullDownMenuItem(
      //   title: 'Delete',
      //   icon: CupertinoIcons.delete,
      //   isDestructive: true,
      //   onTap: () {
      //     _removeItem(message);
      //   },
      // ),
    ];

    await showPullDownMenu(context: context, position: menuRect, items: items);
  }

  void _copyMessage(TextMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied: ${message.text}')));
  }

  void _sendMessage(String? text) async {
    if (text == null || text.trim().isEmpty) return;
    _abortMessage();
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await widget.viewModel.sendChatMessage(text);
      _addTyping();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _abortMessage() async {
    widget.viewModel.abortMessage();
    await Future.delayed(const Duration(milliseconds: 500));
    // _removeTyping();
  }

  void _removeItem(Message item) async {
    // widget.viewModel.removeMessage(item.id);
    await _chatController.removeMessage(item);
    if (_chatController.messages.length == 1) {
      await _chatController.removeMessage(_chatController.messages[0]);
    }
  }

  void _handleAttachmentTap() async {
    await showModalBottomSheet(
      context: context,
      clipBehavior: Clip.hardEdge,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Image'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final image = await picker.pickImage(
                    source: ImageSource.gallery,
                  );

                  if (image != null) {
                    // 1. 读取图片数据并转为 Base64
                    final bytes = await image.readAsBytes();
                    final base64Content = base64Encode(bytes);

                    // 2. 构造附件对象
                    // 简单的 mimeType 处理，可以根据需要增强
                    String mimeType = 'image/jpeg';
                    if (image.path.toLowerCase().endsWith('.png'))
                      mimeType = 'image/png';
                    if (image.path.toLowerCase().endsWith('.gif'))
                      mimeType = 'image/gif';
                    if (image.path.toLowerCase().endsWith('.webp'))
                      mimeType = 'image/webp';

                    final attachment = OutgoingAttachment(
                      base64: base64Content,
                      mimeType: mimeType,
                      fileName: image.name,
                      type: 'image',
                    );

                    // 3. 调用 viewModel 发送消息
                    // 注意：这里我们通常会发送一条描述文字，或者由后端根据附件识别
                    await widget.viewModel.sendChatMessage(
                      image.path,
                      attachments: [attachment],
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_present),
                title: const Text('File'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    withData: true, // 关键：需要数据进行 base64 编码
                  );

                  if (result != null && result.files.isNotEmpty) {
                    final file = result.files.first;
                    final bytes =
                        file.bytes ?? await File(file.path!).readAsBytes();
                    final base64Content = base64Encode(bytes);
                    final attachment = OutgoingAttachment(
                      base64: base64Content,
                      mimeType: file.xFile.mimeType!,
                      fileName: file.name,
                      type: 'file',
                    );

                    await widget.viewModel.sendChatMessage(
                      file.path!,
                      attachments: [attachment],
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _init() async {
    widget.viewModel.beginHistoryLoad();
    widget.viewModel.listModels();
    // widget.viewModel.subscribeSessionMessage();
    _eventSubscription = widget.viewModel.messageEvents?.listen((
      chatMsg,
    ) async {
      final uiMsg = _toUiMessage(chatMsg);
      final existingMessages = _chatController.messages;
      final index = existingMessages.indexWhere((m) => m.id == uiMsg.id);
      if (index != -1) {
        _chatController.updateMessage(existingMessages[index], uiMsg);
      } else {
        _removeTyping();
        _chatController.insertMessage(uiMsg);
      }
    });

    _eventSessionUpdateSubscription = widget.viewModel.sessionUpdateEvents
        ?.listen((messages) {
          _chatController.setMessages(messages.map(_toUiMessage).toList());
        });

    _pendingRunSubscription = widget.viewModel.pendingRunEvents?.listen(
      (lastTextContent) {},
    );
  }

  Future<void> _addTyping() async {
    try {
      await _chatController.insertMessage(
        CustomMessage(
          id: _uuid.v4(),
          authorId: _systemUser.id,
          metadata: {'type': 'typing'},
          createdAt: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {}
  }

  Future<void> _removeTyping() async {
    final typingMessage = _chatController.messages.where(
      (message) => message.metadata?['type'] == 'typing',
    );
    if (typingMessage.isNotEmpty) {
      await _chatController.removeMessage(typingMessage.first);
    }
  }

  void _showThinkOptions(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '思考层级 (Think Level)',
                    style: AppTextStyles.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.viewModel.thinkingOptions.length,
                    itemBuilder: (c, i) {
                      final String think = widget.viewModel.thinkingOptions[i];
                      return ListTile(
                        title: Text(
                          think.toUpperCase(),
                          style: AppTextStyles.bodyLarge,
                        ),
                        trailing:
                            think == widget.viewModel.thinkingDefault
                                ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.secondary,
                                )
                                : const Icon(
                                  Icons.circle_outlined,
                                  color: AppColors.textTertiary,
                                ),
                        onTap: () {
                          widget.viewModel.setSessionThinking(think);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showModelOptions(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('选择模型 (LLM)', style: AppTextStyles.titleMedium),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.viewModel.rawModels?.length ?? 0,
                    itemBuilder: (c, i) {
                      final dynamic model = widget.viewModel.rawModels?[i];
                      return ListTile(
                        title: Text(
                          model?['name'],
                          style: AppTextStyles.bodyLarge,
                        ),
                        trailing:
                            model?['id'] == widget.viewModel.model
                                ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.secondary,
                                )
                                : const Icon(
                                  Icons.circle_outlined,
                                  color: AppColors.textTertiary,
                                ),
                        onTap: () {
                          widget.viewModel.setSessionModel(model?['id']);
                          Navigator.pop(context);
                          _showThinkOptions(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
