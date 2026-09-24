import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
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
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/screen/voice_screen.dart';
import 'package:parrot_app/ui/view_model/chat_viewmodel.dart';
import 'package:parrot_app/ui/widget/hive_chat_controller.dart';
import 'package:parrot_app/ui/widget/composer_action_bar.dart';
import 'package:parrot_app/ui/widget/mic_permission_dialog.dart';
import 'package:parrot_app/ui/widget/my_snack_bar.dart';
import 'package:parrot_app/ui/widget/voice_input_button.dart';
import 'package:parrot_app/util/asr_util.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:parrot_app/util/string_util.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:parrot_app/data/model/message.dart' as model;

enum InputMode { Text, Voice }

class ChatScreen extends StatefulWidget {
  final ChatViewModel viewModel;

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

  final GlobalKey _composerKey = GlobalKey();
  final GlobalKey _modelButtonKey = GlobalKey();

  /// 上一帧「生成中」与否，用来在 `runId` 由非空变空的那一刻收掉 typing 气泡。
  bool _wasRunning = false;

  bool isLive2dShow = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleRunStateChanged);
    _eventSubscription?.cancel();
    _pendingRunSubscription?.cancel();
    _eventSessionUpdateSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  /// 打开图片/文件/视频；用 externalApplication 调系统默认应用（macOS 关键）
  Future<void> _openMedia(BuildContext context, String source) async {
    final url = widget.viewModel.resolveMediaUrl(context, source);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开：$url')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    }
  }

  /// 把一条网关消息转成聊天页的 UI 消息。
  ///
  /// 一条网关消息可能同时带正文和媒体（助手回复正文 + `MEDIA:` 附件），而 UI 的
  /// `Message` 一次只能表达一种内容，所以这里返回列表：正文合并成一个文本气泡，
  /// 每个媒体各自成一个气泡。此前只取 `content.first`，而媒体又排在正文之前，
  /// 于是文件卡片把回复文字整个挤掉了。
  List<Message> _toUiMessages(model.ChatMessage m) {
    String authorId = m.role; // 直接映射 role: user, assistant, system
    if (authorId == 'user') authorId = 'me';

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      m.timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );

    final messages = <Message>[];

    // 正文：把所有 text 内容块合并成一个气泡，顺序保持在媒体之前。
    final textContent = m.content
        .where((c) => c.type == 'text')
        .map((c) => c.text ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');
    if (textContent.isNotEmpty) {
      messages.add(
        TextMessage(
          id: m.id,
          authorId: authorId,
          text: textContent,
          createdAt: createdAt,
          status: MessageStatus.seen,
        ),
      );
    }

    // 媒体：每个带来源的内容块各自成一个气泡（同一条消息里可能有多个附件）。
    for (final media in m.content) {
      final rawSource = media.text;
      if (media.type == 'text' || rawSource == null || rawSource.isEmpty) {
        continue;
      }
      final id = '${m.id}#media${messages.length}';
      if (media.type == 'image') {
        messages.add(
          ImageMessage(
            id: id,
            authorId: authorId,
            size: 0,
            createdAt: createdAt,
            source: _resolveImageSource(rawSource),
          ),
        );
      } else if (media.type == 'file' ||
          media.type == 'video' ||
          media.type == 'audio') {
        messages.add(
          FileMessage(
            id: id,
            authorId: authorId,
            createdAt: createdAt,
            // 文件卡片本身不读盘，点击时由 `_openMedia` 再解析一次。
            source: rawSource,
            name: media.fileName ?? 'file',
          ),
        );
      }
    }

    if (messages.isNotEmpty) return messages;

    // 没有可渲染的正文与媒体时，保留原来的兜底文案。
    final fallback = switch (m.content.isEmpty
        ? 'text'
        : m.content.first.type) {
      'text' => '',
      'toolCall' => 'Tool Call',
      _ => '未知内容',
    };
    return [
      TextMessage(
        id: m.id,
        authorId: authorId,
        text: fallback,
        createdAt: createdAt,
        status: MessageStatus.seen,
      ),
    ];
  }

  /// 图片渲染用的 source —— 交给图片组件之前必须先过这里。
  ///
  /// `flyer_chat_image_message` 内部是 `cross_cache` 的
  /// `CachedNetworkImage(message.source)`，而 `cross_cache` 只认四类 source：
  /// `assets/`、`data:` URI、`http/https/blob`，**其余一律**先
  /// `XFile(source).readAsBytes()` 读盘、再试 `base64Decode`，都失败就抛
  /// `Invalid source: cannot be processed`（`cross_cache.dart` 的 `downloadAndSave`）。
  ///
  /// 网关给的 `MEDIA:` 路径是**网关那台机器上的绝对路径**：桌面端这个文件恰好
  /// 就在本机，读盘蒙对了；移动端读不到盘 → 图片位置一片空白。
  /// 所以：
  /// - 本来就能直接加载的 → 原样返回；
  /// - 本机真实存在的文件（桌面端、自己刚发出去的附件）→ 原样返回，走本地读盘；
  /// - 其余（路径属于网关那台机器）→ 交给 ViewModel 转成 assistant-media URL。
  ///
  /// 注意「能否直接加载」不能只看 `uri.scheme` 非空：Windows 盘符路径
  ///（`C:\...`）会被解析成 `scheme == 'c'`，所以这里逐个列出可加载的 scheme。
  String _resolveImageSource(String source) {
    final scheme = Uri.tryParse(source)?.scheme ?? '';
    final loadableDirectly =
        scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'data' ||
        scheme == 'blob' ||
        source.startsWith('assets/');
    if (loadableDirectly) return source;
    if (File(source).existsSync()) return source;
    return widget.viewModel.resolveMediaUrl(context, source);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.menu),
                tooltip: '打开侧边栏',
                onPressed: () {
                  indexController.switchSideBarVisible();
                },
              ),
              centerTitle: false,
              title: const Text('ParrotClaw'),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    onPressed: () {
                      if (kIsMobile) {
                        context.go(Routes.voice);
                      }
                      if (kIsDesktop) {
                        setState(() {
                          isLive2dShow = !isLive2dShow;
                        });
                      }
                    },
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            body: Stack(
              children: [
                ListenableBuilder(
                  listenable: widget.viewModel,
                  builder: (context, child) {
                    if (widget.viewModel.isHistoryLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Chat(
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
                              onTap: () => _openMedia(context, message.source),
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
                            (context) => CustomComposer(
                              key: _composerKey,
                              // 「打断」已从上方工具栏挪到输入行（发送键的位置），
                              // 生成中与否由 composer 自己读 viewModel.runId 判断。
                              viewModel: widget.viewModel,
                              topWidget: ComposerActionBar(
                                buttons: [
                                  ComposerActionButton(
                                    visible: true,
                                    icon: Icons.delete_sweep,
                                    title: 'Clear',
                                    onPressed: _resetConversation,
                                  ),
                                  ComposerActionButton(
                                    key: _modelButtonKey,
                                    visible: true,
                                    icon: Icons.psychology_outlined,
                                    title: widget.viewModel.model ?? '模型',
                                    onPressed: () => _showModelOptions(context),
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
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
                              onTap: () => _openMedia(context, message.source),
                              child: FlyerChatFileMessage(
                                message: message,
                                index: index,
                                receivedSizeTextStyle: TextStyle(fontSize: 0),
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
                              !isSystemMessage &&
                              isLastInGroup &&
                              isRemoved != true;
                          final isCurrentUser =
                              message.authorId == _currentUser.id;
                          final shouldShowUsername =
                              !isSystemMessage &&
                              isFirstInGroup &&
                              isRemoved != true;

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
                            horizontalPadding:
                                (message is SystemMessage) ? 0 : 8,
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
                    );
                  },
                ),
                // 「按住说话」不再浮在输入框上方：录音按钮已收进 CustomComposer，
                // 与输入框、发送键同一行（见 _CustomComposerState._inputMode）。
              ],
            ),
          ),
        ),
        Visibility(
          visible: isLive2dShow,
          child: SizedBox(
            width: 400,
            child: VoiceScreen(viewModel: context.read()),
          ),
        ),
      ],
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
            EdgeTTSUtil().speak(StringUtil.cleanTextForTts(message.text));
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
    MySnackBar.showInfo(context, 'Copied: ${message.text}');
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
      MySnackBar.showError(context, e.toString());
    }
  }

  /// 清空当前会话：先清本地消息，再让网关重置。
  /// 必须等 sendChatMessage 完成并接住异常，否则失败时界面只会静默清空。
  Future<void> _resetConversation() async {
    _chatController.setMessages([]);
    try {
      await widget.viewModel.sendChatMessage('/reset');
    } catch (e) {
      if (!mounted) return;
      MySnackBar.showError(context, e.toString());
    }
  }

  void _abortMessage() async {
    // 「正在输入」气泡由 [_handleRunStateChanged] 在 run 结束时统一收掉：
    // 打断后网关不会再推消息，这里若不管，typing 就会一直挂着。
    await widget.viewModel.abortMessage();
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
                      mimeType: file.xFile.mimeType ?? '',
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
    // run 结束（正常 final / 被中断 / 报错都会把 runId 清空）时收掉 typing。
    // 打断这条路径网关不会再推消息，只能靠这里兜。
    _wasRunning = widget.viewModel.runId != '';
    widget.viewModel.addListener(_handleRunStateChanged);
    _eventSubscription = widget.viewModel.messageEvents?.listen((
      chatMsg,
    ) async {
      // 一条网关消息可能拆成多个 UI 气泡（正文 + 附件），逐个插入 / 更新。
      final existingMessages = _chatController.messages;
      for (final uiMsg in _toUiMessages(chatMsg)) {
        final index = existingMessages.indexWhere((m) => m.id == uiMsg.id);
        if (index != -1) {
          _chatController.updateMessage(existingMessages[index], uiMsg);
        } else {
          _removeTyping();
          _chatController.insertMessage(uiMsg);
        }
      }
    });
    _eventSessionUpdateSubscription = widget.viewModel.sessionUpdateEvents
        ?.listen((messages) {
          _chatController.setMessages(messages.expand(_toUiMessages).toList());
        });
    _pendingRunSubscription = widget.viewModel.pendingRunEvents?.listen(
      (lastTextContent) {},
    );
  }

  /// run 结束（`runId` 由非空变为空）时收掉「正在输入」气泡。
  ///
  /// 此前只在「收到新消息」时清 typing，而打断 / 报错这两条路径网关都不会再推
  /// 消息，于是气泡会一直挂在那里 —— 典型表现是「打断后 Typing 不消失」。
  /// 挂在 run 的生死上就同时覆盖 final / aborted / error 三种收尾。
  void _handleRunStateChanged() {
    final isRunning = widget.viewModel.runId != '';
    final justStopped = _wasRunning && !isRunning;
    _wasRunning = isRunning;
    if (justStopped) unawaited(_removeTyping());
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
    } catch (e) {
      // 「正在输入」只是装饰性提示，插入失败不应影响消息发送本身。
      debugPrint('Failed to insert typing indicator: $e');
    }
  }

  Future<void> _removeTyping() async {
    // 全部清掉（不是只清第一个）：任何一次漏收都可能在列表里留下多余气泡。
    final typingMessages =
        _chatController.messages
            .where((message) => message.metadata?['type'] == 'typing')
            .toList();
    for (final message in typingMessages) {
      await _chatController.removeMessage(message);
    }
  }

  Rect? _buttonRect(GlobalKey key) {
    final buttonContext = key.currentContext;
    final renderObject = buttonContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _showModelOptions(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    final modelButtonRect = _buttonRect(_modelButtonKey);
    if (modelButtonRect == null) return;

    final items =
        (widget.viewModel.rawModels ?? []).whereType<Map>().map((model) {
          final modelId = model['id']?.toString();
          final modelName = model['name']?.toString() ?? modelId ?? '未知模型';
          return PullDownMenuItem(
            title: modelName,
            icon:
                modelId == widget.viewModel.model
                    ? CupertinoIcons.check_mark_circled
                    : CupertinoIcons.circle,
            tapHandler: PullDownMenuItem.noPopTapHandler,
            onTap: () {
              _showThinkingOptionsForModel(context, modelButtonRect, modelId);
            },
          );
        }).toList();

    showPullDownMenu(
      context: context,
      position: modelButtonRect,
      items: items,
      itemsOrder: PullDownMenuItemsOrder.upwards,
    );
  }

  void _showThinkingOptionsForModel(
    BuildContext context,
    Rect modelButtonRect,
    String? model,
  ) {
    final options = widget.viewModel.thinkingOptions;
    if (options.isEmpty) {
      unawaited(_updateSessionConfig(model: model));
      return;
    }

    final items =
        options.map((option) {
          final thinkingLevel = option.toString();
          return PullDownMenuItem(
            title: thinkingLevel.toUpperCase(),
            icon:
                thinkingLevel == widget.viewModel.thinkingDefault
                    ? CupertinoIcons.check_mark_circled
                    : CupertinoIcons.circle,
            onTap: () {
              unawaited(
                _updateSessionConfig(
                  model: model,
                  thinkingLevel: thinkingLevel,
                ),
              );
            },
          );
        }).toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final thinkingPosition = Rect.fromLTWH(
      modelButtonRect.right,
      modelButtonRect.top,
      0,
      modelButtonRect.height,
    );
    showPullDownMenu(
      context: context,
      position: thinkingPosition,
      items: items,
      menuOffset: screenWidth - modelButtonRect.right < 260 ? -16 : 16,
    );
  }

  Future<void> _updateSessionConfig({
    String? model,
    String? thinkingLevel,
  }) async {
    try {
      await widget.viewModel.setSessionConfig(
        model: model,
        thinkingLevel: thinkingLevel,
      );
    } catch (error) {
      if (!mounted) return;
      MySnackBar.showError(context, error.toString());
    }
  }
}

class CustomComposer extends StatefulWidget {
  final Widget? topWidget;

  /// 生成中要就地显示「打断」按钮，判断依据是网关的 `runId`
  ///（`runId != ''` 即有一次生成在跑），所以直接把 viewModel 传进来。
  final ChatViewModel viewModel;

  const CustomComposer({
    super.key,
    this.topWidget,
    required this.viewModel,
  });

  @override
  State<CustomComposer> createState() => _CustomComposerState();
}

class _CustomComposerState extends State<CustomComposer> {
  final _key = GlobalKey();
  late final FocusNode _focusNode;

  /// 输入框控制器跟着 composer 一起生灭：ChatScreen 不再持有它，
  /// 拖拽贴路径之类的操作也就能就地读写，不用再把 controller 传出去。
  final _controller = TextEditingController();

  /// 输入模式：文本 ⇄ 语音。语音模式下输入框让位给「按住说话」按钮，
  /// 录音与 ASR 都由本组件自己管，不再由 ChatScreen 透传回调。
  InputMode _inputMode = InputMode.Text;

  /// 桌面端：是否有文件正被拖到输入框上方（用于显示高亮反馈）。
  bool _isFileDragging = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _initTalk();
    // 输入框会随行数长高，高度一变就得重新上报，否则聊天列表底部留白不跟着变，
    // 长高的 composer 会把最后一条消息盖住。（setHeight 只在真的变了才通知，不担心刷。）
    _controller.addListener(_scheduleMeasure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// 注册 ASR 回调。识别结果直接走 [_handleSubmitted]（等价于用户点发送），
  /// 失败提示也用本组件的 context —— 所以外面不需要再传任何回调进来。
  void _initTalk() {
    ASRUtil().setCallbacks(
      onTextResult: _handleSubmitted,
      // 录音/初始化失败不再静默：就地提示原因（如 Windows 麦克风权限）
      onError: (String error) {
        if (!mounted) return;
        if (error == ASRUtil.kMicDeviceUnavailable) {
          showMicDeviceDialog(context);
        } else {
          MySnackBar.showError(context, error);
        }
      },
    );
  }

  /// 文本 ⇄ 语音切换。切到语音前清空并收起键盘，避免键盘挡住「按住说话」。
  void _toggleInputMode() {
    if (_inputMode == InputMode.Voice) {
      setState(() => _inputMode = InputMode.Text);
    } else {
      _controller.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _inputMode = InputMode.Voice);
    }
    // 输入区高度变了，重新量一次，否则聊天列表底部会留白或被挡。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _startRecording() {
    // ASRUtil 是单例、setCallbacks 全局覆盖，VoiceScreen（手机语音通话页 /
    // 桌面 Live2D 面板）也会注册同一套回调；从那边退出后回调仍指向已销毁的
    // 页面，识别结果就丢了。所以每次开始录音前重新认领一次，保证结果回到本输入框。
    _initTalk();
    ASRUtil().start();
  }

  void _stopRecording() {
    ASRUtil().stop();
  }

  /// 桌面端把输入框包成文件拖入区：拖入时高亮提示，松手后把文件绝对路径
  /// 追加进输入框（只贴路径，不做上传）。
  ///
  /// 移动端没有拖拽语义，直接原样返回。
  Widget _wrapFileDrop(Widget child) {
    if (!kIsDesktop) return child;

    return DropTarget(
      onDragEntered: (_) {
        if (mounted) setState(() => _isFileDragging = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _isFileDragging = false);
      },
      onDragDone: (detail) {
        if (mounted) setState(() => _isFileDragging = false);
        _insertDroppedPaths(detail.files.map((f) => f.path).toList());
      },
      child: Stack(
        children: [
          child,
          if (_isFileDragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '松开鼠标，把文件路径插入输入框',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 把拖入的文件路径追加到输入框末尾。
  ///
  /// 含空格或 shell 特殊字符的路径会用双引号包住，方便 agent 直接当参数用。
  void _insertDroppedPaths(List<String> paths) {
    final cleaned = paths.where((p) => p.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) return;

    final inserted = cleaned.map(_quotePathIfNeeded).join(' ');
    final current = _controller.text;
    final separator = current.isEmpty || current.endsWith(' ') ? '' : ' ';
    final next = '$current$separator$inserted ';

    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );

    // 语音模式下输入框是隐藏的，贴完路径切回文本模式，否则用户看不到。
    if (_inputMode == InputMode.Voice) {
      setState(() => _inputMode = InputMode.Text);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  /// 路径含空格/引号等字符时加双引号，避免被当成多个参数。
  String _quotePathIfNeeded(String path) {
    if (!RegExp(r'''[\s"'$`&()\[\]{};|<>*?!]''').hasMatch(path)) return path;
    return '"${path.replaceAll('"', r'\"')}"';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 回车发送，Shift+回车换行（此前是反的：Shift+回车才会发送）。
    // Shift+回车必须返回 ignored，把换行交回给 TextField 自己处理 ——
    // 返回 handled 会连换行一起吃掉。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // 长按回车会连续触发 KeyDown，但首次发送后输入框已清空，
    // _handleSubmitted 的空文本保护会让后续几次变成 no-op。
    _handleSubmitted(_controller.text);
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant CustomComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleMeasure);
    _controller.dispose();
    ASRUtil().stop();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final onAttachmentTap = context.read<OnAttachmentTapCallback?>();
    final theme = context.select(
      (ChatTheme t) => (
        bodyMedium: t.typography.bodyMedium,
        onSurface: t.colors.onSurface,
        surfaceContainerHigh: t.colors.surfaceContainerHigh,
        surfaceContainerLow: t.colors.surfaceContainerLow,
      ),
    );

    // 「按住说话」条的底色（VoiceInputButton 内部硬编码了同一个值）。
    // 语音模式下键盘按钮垫同款底色、紧贴录音条，两段连成一整条。
    final voiceBarColor = ChatTheme.dark().colors.surface;
    final isVoiceMode = _inputMode == InputMode.Voice;

    // 生成中（网关侧有 runId 在跑）：发送键与录音/语音键都让位给「打断」按钮。
    final isRunning = widget.viewModel.runId != '';

    // 发送/语音按钮的尺寸：桌面端压到 32（原来吃满 IconButton 默认的 48），
    // 移动端仍保留 44 的触摸目标，别把可点区域缩到手指够不着。
    final actionSize = kIsDesktop ? 32.0 : 44.0;
    final actionIconSize = kIsDesktop ? 18.0 : 22.0;

    // 关键：IconButton 外层有 _InputPadding，主题的 tapTargetSize 是 padded（默认）
    // 时它会把占位强行撑到 48×48 —— 只设 constraints / iconSize 是没用的，
    // 必须 shrinkWrap 才能真的缩到 actionSize。
    final actionButtonStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    // 输入框「单行」的高度：contentPadding 上下 12 + 14px 字型 ≈ 48（实测单行 48）。
    // 语音条和右侧按钮按它对齐，所以切模式时高度不会跳。
    // 注意：这只是对齐基准，**不是给输入框设的上限** —— 多行时输入框要跟着长高
    //（实测 2 行 66、3 行 87），整个 composer 就该被顶上去。
    const inputSingleLineHeight = 48.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: Container(
          key: _key,
          color: theme.surfaceContainerLow,
          child: Column(
            children: [
              if (widget.topWidget != null) widget.topWidget!,
              Padding(
                padding: EdgeInsets.only(
                  bottom: bottomSafeArea,
                ).add(const EdgeInsets.all(8.0)),
                child: Row(
                  children: [
                    onAttachmentTap != null
                        ? IconButton(
                          icon: const Icon(Icons.attachment),
                          constraints: BoxConstraints.tightFor(
                            width: actionSize,
                            height: actionSize,
                          ),
                          iconSize: actionIconSize,
                          color: theme.onSurface.withValues(alpha: 0.5),
                          onPressed: onAttachmentTap,
                        )
                        : const SizedBox.shrink(),
                    const SizedBox(width: 4),
                      Expanded(
                        child:
                            isVoiceMode
                                ? SizedBox(
                                    height: inputSingleLineHeight,
                                    child: VoiceInputButton(
                                      startRecording: _startRecording,
                                      stopRecording: _stopRecording,
                                    ),
                                  )
                                : _wrapFileDrop(
                                  TextField(
                                    controller: _controller,
                                    decoration: InputDecoration(
                                      hintText: '说点什么...',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      hintStyle: theme.bodyMedium.copyWith(
                                        color: theme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      border: const OutlineInputBorder(
                                        borderSide: BorderSide.none,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(24),
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: theme.surfaceContainerHigh
                                          .withValues(alpha: 0.8),
                                      hoverColor: Colors.transparent,
                                    ),
                                    style: theme.bodyMedium.copyWith(
                                      color: theme.onSurface,
                                    ),
                                    onSubmitted: _handleSubmitted,
                                    textInputAction: TextInputAction.newline,
                                    autocorrect: true,
                                    autofocus: false,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    focusNode: _focusNode,
                                    minLines: 1,
                                    maxLines: 3,
                                  ),
                                ),
                      ),
                    // 生成中：发送键换成「打断」（原先在上方工具栏的 Abort）。
                    if (isRunning) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '打断',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tightFor(
                          width: actionSize,
                          height: actionSize,
                        ),
                        iconSize: actionIconSize,
                        style: actionButtonStyle,
                        icon: const Icon(Icons.stop),
                        color: AppColors.secondary,
                        onPressed: () => widget.viewModel.abortMessage(),
                      ),
                    ] else if (!isVoiceMode) ...[
                      // 语音模式下说话即发送，发送键不再占位。
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '发送',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tightFor(
                          width: actionSize,
                          height: actionSize,
                        ),
                        iconSize: actionIconSize,
                        style: actionButtonStyle,
                        icon: const Icon(Icons.send),
                        color: theme.onSurface.withValues(alpha: 0.5),
                        onPressed: () => _handleSubmitted(_controller.text),
                      ),
                    ],
                    // 语音开关（最右边这个切换模式的按钮）：文本为空时才出现
                    //（已经在打字就不占位），语音模式下常驻以便切回键盘，
                    // 并垫上录音条同款底色。
                    // 生成中隐藏：这段位置让给左侧输入框自己撑开。
                    if (!isRunning)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          if (!isVoiceMode && value.text.isNotEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            height: inputSingleLineHeight,
                            width: actionSize + 4,
                            alignment: Alignment.center,
                            color: isVoiceMode ? voiceBarColor : null,
                            child: IconButton(
                              tooltip: isVoiceMode ? '切换键盘输入' : '语音输入',
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints.tightFor(
                                width: actionSize,
                                height: actionSize,
                              ),
                              iconSize: actionIconSize,
                              style: actionButtonStyle,
                              icon: Icon(
                                isVoiceMode
                                    ? Icons.keyboard_alt_outlined
                                    : Icons.mic_outlined,
                              ),
                              color: theme.onSurface.withValues(alpha: 0.5),
                              onPressed: _toggleInputMode,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _measure() {
    if (!mounted) return;

    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      final bottomSafeArea = MediaQuery.of(context).padding.bottom;

      context.read<ComposerHeightNotifier>().setHeight(height - bottomSafeArea);
    }
  }

  void _handleSubmitted(String text) {
    if (text.isNotEmpty) {
      context.read<OnMessageSendCallback?>()?.call(text);
      _controller.clear();
    }
  }
}
