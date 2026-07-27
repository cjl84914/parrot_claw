import 'dart:async';
import 'package:flutter_chat_core/flutter_chat_core.dart';

class HiveChatController
    with UploadProgressMixin, ScrollToMessageMixin
    implements ChatController {

  final _operationsController = StreamController<ChatOperation>.broadcast();

  // 缓存 UI 消息列表
  List<Message> _messages = [];

  @override
  List<Message> get messages => _messages;

  @override
  Future<void> insertMessage(
      Message message, {
        int? index,
        bool animated = true,
      }) async {

    if (index != null && index >= 0 && index <= _messages.length) {
      _messages.insert(index, message);
    } else {
      _messages.add(message);
    }

    // 通知 UI
    _operationsController.add(
      ChatOperation.insert(message, index ?? _messages.length - 1, animated: animated),
    );
  }

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) async {
    if (oldMessage == newMessage) return;

    final index = _messages.indexWhere((m) => m.id == oldMessage.id);
    if (index != -1) {
      _messages[index] = newMessage;
      _operationsController.add(
        ChatOperation.update(oldMessage, newMessage, index),
      );
    }
  }

  @override
  Future<void> removeMessage(Message message, {bool animated = true}) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _messages.removeAt(index);
      _operationsController.add(
        ChatOperation.remove(message, index, animated: animated),
      );
    }
  }

  @override
  Future<void> setMessages(
      List<Message> messages, {
        bool animated = true,
      }) async {
    _messages = List.from(messages);
    _operationsController.add(
      ChatOperation.set(_messages, animated: animated),
    );
  }

  @override
  Future<void> insertAllMessages(
      List<Message> messages, {
        int? index,
        bool animated = true,
      }) async {
    final targetIndex = index ?? 0;
    _messages.insertAll(targetIndex, messages);

    _operationsController.add(
      ChatOperation.insertAll(messages, targetIndex, animated: animated),
    );
  }

  @override
  Stream<ChatOperation> get operationsStream => _operationsController.stream;

  @override
  void dispose() {
    _operationsController.close();
    disposeUploadProgress();
    disposeScrollMethods();
  }
}
