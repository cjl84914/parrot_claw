import 'dart:convert';

/// OpenClaw Gateway protocol version advertised by the generated Android model.
const int openClawProtocolVersion = 4;
const int openClawMinProtocolVersion = 3;

/// A JSON document that must remain a string at the OpenClaw protocol boundary.
///
/// This is intentionally not decoded by the generic request encoder. Callers
/// can use [decode] only when they explicitly need to inspect the document.
class OpenClawRawJson {
  final String text;

  const OpenClawRawJson(this.text);

  factory OpenClawRawJson.fromValue(Object? value) {
    return OpenClawRawJson(jsonEncode(value));
  }

  dynamic decode() => jsonDecode(text);

  @override
  String toString() => text;
}

class OpenClawRequestFrame {
  final String id;
  final String method;
  final Map<String, dynamic>? params;
  final String? traceparent;

  const OpenClawRequestFrame({
    required this.id,
    required this.method,
    this.params,
    this.traceparent,
  });

  Map<String, dynamic> toJson() => {
        'type': 'req',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
        if (traceparent != null) 'traceparent': traceparent,
      };
}

class OpenClawResponseFrame {
  final String id;
  final bool ok;
  final dynamic payload;
  final OpenClawProtocolError? error;

  const OpenClawResponseFrame({
    required this.id,
    required this.ok,
    this.payload,
    this.error,
  });

  factory OpenClawResponseFrame.fromJson(Map<String, dynamic> json) {
    final rawError = json['error'];
    return OpenClawResponseFrame(
      id: json['id']?.toString() ?? '',
      ok: json['ok'] == true,
      payload: json['payload'],
      error: rawError is Map
          ? OpenClawProtocolError.fromJson(rawError.cast<String, dynamic>())
          : null,
    );
  }
}

class OpenClawEventFrame {
  final String event;
  final dynamic payload;
  final int? seq;
  final OpenClawStateVersion? stateVersion;

  const OpenClawEventFrame({
    required this.event,
    this.payload,
    this.seq,
    this.stateVersion,
  });

  factory OpenClawEventFrame.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['stateVersion'];
    return OpenClawEventFrame(
      event: json['event']?.toString() ?? '',
      payload: json['payload'],
      seq: (json['seq'] as num?)?.toInt(),
      stateVersion: rawVersion is Map
          ? OpenClawStateVersion.fromJson(rawVersion.cast<String, dynamic>())
          : null,
    );
  }
}

class OpenClawProtocolError {
  final String code;
  final String message;
  final Map<String, dynamic> details;
  final bool? retryable;
  final int? retryAfterMs;

  const OpenClawProtocolError({
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
    this.retryable,
    this.retryAfterMs,
  });

  factory OpenClawProtocolError.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    return OpenClawProtocolError(
      code: json['code']?.toString() ?? 'UNKNOWN',
      message: json['message']?.toString() ?? 'Gateway error',
      details: rawDetails is Map
          ? rawDetails.cast<String, dynamic>()
          : const <String, dynamic>{},
      retryable: json['retryable'] as bool?,
      retryAfterMs: (json['retryAfterMs'] as num?)?.toInt(),
    );
  }
}

class OpenClawStateVersion {
  final int presence;
  final int health;

  const OpenClawStateVersion({required this.presence, required this.health});

  factory OpenClawStateVersion.fromJson(Map<String, dynamic> json) {
    return OpenClawStateVersion(
      presence: (json['presence'] as num?)?.toInt() ?? 0,
      health: (json['health'] as num?)?.toInt() ?? 0,
    );
  }
}

class OpenClawDevicePairSetupCodeResponse {
  final String setupCode;
  final String gatewayUrl;
  final String auth;
  final String urlSource;
  final String? setupId;
  final String? joinUrl;
  final String? qrDataUrl;
  final List<String>? gatewayUrls;
  final String? access;
  final bool? accessDowngraded;
  final int? expiresAtMs;

  const OpenClawDevicePairSetupCodeResponse({
    required this.setupCode,
    required this.gatewayUrl,
    required this.auth,
    required this.urlSource,
    this.setupId,
    this.joinUrl,
    this.qrDataUrl,
    this.gatewayUrls,
    this.access,
    this.accessDowngraded,
    this.expiresAtMs,
  });

  factory OpenClawDevicePairSetupCodeResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final setupCode = json['setupCode'] as String?;
    final gatewayUrl = json['gatewayUrl'] as String?;
    final auth = json['auth'] as String?;
    final urlSource = json['urlSource'] as String?;
    if (setupCode == null || setupCode.trim().isEmpty) {
      throw const FormatException(
        'device.pair.setupCode response missing setupCode',
      );
    }
    if (gatewayUrl == null || gatewayUrl.trim().isEmpty) {
      throw const FormatException(
        'device.pair.setupCode response missing gatewayUrl',
      );
    }
    if (auth == null || auth.trim().isEmpty) {
      throw const FormatException(
        'device.pair.setupCode response missing auth',
      );
    }
    if (urlSource == null || urlSource.trim().isEmpty) {
      throw const FormatException(
        'device.pair.setupCode response missing urlSource',
      );
    }
    return OpenClawDevicePairSetupCodeResponse(
      setupCode: setupCode,
      gatewayUrl: gatewayUrl,
      auth: auth,
      urlSource: urlSource,
      setupId: json['setupId'] as String?,
      joinUrl: json['joinUrl'] as String?,
      qrDataUrl: json['qrDataUrl'] as String?,
      gatewayUrls: (json['gatewayUrls'] as List?)?.whereType<String>().toList(),
      access: json['access'] as String?,
      accessDowngraded: json['accessDowngraded'] as bool?,
      expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
    );
  }
}

class OpenClawNodeInvokeRequest {
  final String id;
  final String nodeId;
  final String command;
  final OpenClawRawJson? paramsJson;
  final int? timeoutMs;
  final String? idempotencyKey;

  const OpenClawNodeInvokeRequest({
    required this.id,
    required this.nodeId,
    required this.command,
    this.paramsJson,
    this.timeoutMs,
    this.idempotencyKey,
  });

  factory OpenClawNodeInvokeRequest.fromJson(Map<String, dynamic> json) {
    final raw = json['paramsJSON'];
    return OpenClawNodeInvokeRequest(
      id: json['id']?.toString() ?? '',
      nodeId: json['nodeId']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
      paramsJson: raw is String ? OpenClawRawJson(raw) : null,
      timeoutMs: (json['timeoutMs'] as num?)?.toInt(),
      idempotencyKey: json['idempotencyKey']?.toString(),
    );
  }
}

class OpenClawProtocolCatalog {
  OpenClawProtocolCatalog._();

  static const methods = <String>{
    'health', 'diagnostics.stability', 'doctor.memory.status',
    'doctor.memory.dreamDiary', 'doctor.memory.backfillDreamDiary',
    'doctor.memory.resetDreamDiary', 'doctor.memory.resetGroundedShortTerm',
    'doctor.memory.repairDreamingArtifacts', 'doctor.memory.dedupeDreamDiary',
    'logs.tail', 'channels.status', 'channels.start', 'channels.stop',
    'channels.logout', 'status', 'usage.status', 'usage.cost', 'tts.status',
    'tts.providers', 'tts.personas', 'tts.enable', 'tts.disable', 'tts.convert',
    'tts.setProvider', 'tts.setPersona', 'exec.approvals.get',
    'exec.approvals.set', 'exec.approvals.node.get', 'exec.approvals.node.set',
    'exec.approval.get', 'exec.approval.list', 'exec.approval.request',
    'exec.approval.waitDecision', 'exec.approval.resolve',
    'exec.approval.grants.list', 'exec.approval.grants.revoke',
    'question.request', 'question.waitAnswer', 'question.resolve',
    'question.get', 'question.list', 'plugin.approval.list',
    'plugin.approval.request', 'plugin.approval.waitDecision',
    'plugin.approval.resolve', 'plugins.uiDescriptors', 'plugins.sessionAction',
    'openclaw.chat', 'openclaw.chat.history', 'openclaw.changes.list',
    'openclaw.approval.list', 'openclaw.setup.detect',
    'openclaw.setup.activate', 'openclaw.setup.activate.start',
    'openclaw.setup.auth.start', 'openclaw.setup.prepare.start', 'wizard.start',
    'wizard.next', 'wizard.cancel', 'wizard.status', 'talk.catalog',
    'talk.config', 'talk.client.create', 'talk.client.transcript',
    'talk.client.close', 'talk.client.toolCall', 'talk.client.steer',
    'talk.session.create', 'talk.session.appendAudio',
    'talk.session.cancelOutput', 'talk.session.acknowledgeMark',
    'talk.session.submitToolResult', 'talk.session.steer', 'talk.session.close',
    'talk.speak', 'talk.mode', 'commands.list', 'models.list', 'models.authStatus',
    'models.authLogout', 'tools.catalog', 'tools.effective', 'tools.invoke',
    'mcp.app.view', 'mcp.app.listTools', 'mcp.app.listResources',
    'mcp.app.listResourceTemplates', 'mcp.app.readResource', 'mcp.app.callTool',
    'mcp.app.updateModelContext', 'board.get', 'board.update',
    'board.widget.put', 'board.widget.grant', 'board.widget.appView',
    'board.event', 'audit.list', 'audit.activity.list', 'users.list',
    'users.self', 'users.linkEmail', 'users.setDisplayName', 'users.setAvatar',
    'users.setRole', 'tasks.list', 'tasks.get', 'tasks.cancel',
    'taskSuggestions.list', 'taskSuggestions.create', 'taskSuggestions.accept',
    'taskSuggestions.dismiss', 'environments.list', 'environments.status',
    'worktrees.list', 'worktrees.branches', 'fs.listDir', 'worktrees.create',
    'worktrees.remove', 'worktrees.restore', 'worktrees.gc', 'agents.list',
    'agents.create', 'agents.update', 'agents.delete', 'agents.files.list',
    'agents.files.get', 'agents.files.set', 'sessions.files.list',
    'sessions.files.get', 'sessions.files.set', 'sessions.files.reveal',
    'artifacts.list', 'artifacts.get', 'artifacts.download', 'skills.status',
    'skills.search', 'skills.detail', 'skills.securityVerdicts', 'skills.skillCard',
    'skills.bins', 'skills.upload.begin', 'skills.upload.chunk',
    'skills.upload.commit', 'skills.install', 'skills.update',
    'skills.curator.status', 'skills.curator.pin', 'skills.curator.unpin',
    'skills.curator.restore', 'skills.proposals.list', 'skills.proposals.inspect',
    'skills.proposals.historyStatus', 'skills.proposals.historyScan',
    'skills.proposals.create', 'skills.proposals.update', 'skills.proposals.revise',
    'skills.proposals.requestRevision', 'skills.proposals.apply',
    'skills.proposals.reject', 'skills.proposals.quarantine', 'update.status',
    'update.run', 'voicewake.get', 'voicewake.set', 'secrets.reload',
    'secrets.resolve', 'voicewake.routing.get', 'sessions.list',
    'sessions.subscribe', 'sessions.messages.subscribe',
    'sessions.messages.unsubscribe', 'sessions.viewers.set', 'sessions.preview',
    'sessions.describe', 'sessions.compaction.list', 'sessions.compaction.branch',
    'sessions.compaction.restore', 'sessions.branches.list',
    'sessions.branches.switch', 'sessions.rewind', 'sessions.fork',
    'sessions.create', 'sessions.recover', 'sessions.send', 'sessions.abort',
    'sessions.patch', 'sessions.goal.update', 'sessions.goal.clear',
    'sessions.pluginPatch', 'sessions.cleanup', 'sessions.reset', 'sessions.delete',
    'sessions.compact', 'sessions.groups.list', 'sessions.groups.defaults',
    'sessions.groups.put', 'sessions.groups.rename', 'sessions.groups.update',
    'sessions.groups.delete', 'last-heartbeat', 'set-heartbeats', 'wake',
    'node.pair.list', 'node.pair.approve', 'node.pair.reject', 'node.pair.remove',
    'device.pair.list', 'device.pair.approve', 'device.pair.reject',
    'device.pair.remove', 'device.pair.rename', 'device.token.rotate',
    'device.token.revoke', 'device.pair.setupCode', 'device.pair.setupStatus',
    'node.rename', 'node.list', 'node.describe', 'node.pluginSurface.refresh',
    'node.pluginTools.update', 'node.skills.update', 'node.runnerInventory.update',
    'node.pending.drain', 'node.pending.enqueue', 'node.invoke',
    'node.pending.pull', 'node.pending.ack', 'node.invoke.progress',
    'node.invoke.result', 'node.event', 'cron.get', 'cron.list', 'cron.status',
    'cron.scratch.get', 'cron.scratch.set', 'cron.add', 'cron.update',
    'cron.remove', 'cron.run', 'cron.runs', 'gateway.identity.get',
    'gateway.restart.preflight', 'gateway.restart.request', 'system-presence',
    'system-event', 'message.action', 'conversations.send', 'conversations.turn',
    'conversations.turn.cancel', 'send', 'agent', 'agent.identity.get',
    'agent.wait', 'chat.history', 'chat.startup', 'chat.metadata',
    'chat.message.get', 'chat.abort', 'chat.send', 'terminal.open',
    'terminal.input', 'terminal.resize', 'terminal.close', 'channels.pairing.list',
    'channels.pairing.approve', 'channels.pairing.dismiss', 'assistant.media.get',
    'sessions.get', 'sessions.resolve', 'sessions.usage',
    'sessions.usage.timeseries', 'sessions.usage.logs', 'poll', 'sessions.steer',
    'push.test', 'attach.grant', 'attach.revoke', 'push.web.vapidPublicKey',
    'push.web.subscribe', 'push.web.unsubscribe', 'push.web.test',
    'push.web.preferences.get', 'push.web.preferences.set', 'config.openFile',
    'connect', 'chat.inject', 'nativeHook.invoke', 'web.login.start',
    'web.login.wait', 'terminal.attach', 'terminal.list',
    'controlUi.githubPreview', 'system.info', 'agents.workspace.list',
    'agents.workspace.get', 'tts.speak', 'plugins.list', 'plugins.search',
    'plugins.install', 'plugins.setEnabled', 'plugins.uninstall', 'plugins.refresh',
    'controlUi.sessionPullRequests.subscribe', 'controlUi.sessionPreview',
    'gateway.suspend.prepare', 'gateway.suspend.status', 'gateway.suspend.resume',
    'chat.toolTitles', 'sessions.diff', 'openclaw.setup.verify',
    'environments.create', 'environments.destroy', 'sessions.catalog.list',
    'sessions.catalog.read', 'terminal.upload', 'sessions.catalog.continue',
    'sessions.catalog.archive', 'approval.get', 'approval.resolve',
    'sessions.search', 'sessions.dispatch', 'sessions.reclaim', 'models.probe',
    'migrations.memory.plan', 'migrations.memory.apply', 'ui.command',
    'approval.history', 'plugin.surface.refresh', 'conversations.list',
    'session.discussion.info', 'session.discussion.open', 'board.prompt.authorize',
    'board.data.read', 'board.action', 'sessions.observer.visibility',
    'session.visibility.set', 'session.members.list', 'session.members.add',
    'session.members.remove', 'session.suggestions.add', 'session.suggestions.list',
    'session.suggestions.resolve', 'session.typing', 'sessions.companion.ask',
    'sessions.companion.state', 'sessions.companion.reset', 'memory.search',
    'skills.proposals.events.list', 'skills.proposals.evaluate', 'hooks.status',
    'tasks.retry', 'tasks.dismiss', 'audit.run.inspect', 'sessions.patchMany',
    'update.hold', 'sessions.catalog.startTerminal', 'worker.desktop.observe',
    'projects.list', 'projects.register', 'projects.remove', 'worker.desktop.launch',
    'secrets.store.list', 'secrets.store.set', 'secrets.store.delete',
    'users.prefs.get', 'users.prefs.set', 'projects.add', 'projects.searchRemote',
    'desktop.observe', 'desktop.launch', 'device.scopes.requestUpgrade',
    'device.scopes.waitUpgrade', 'portal.list', 'portal.open', 'portal.close',
    'sessions.move', 'sessions.assignOwner', 'progressCard.get',
    'progressCard.put', 'tools.github.status', 'tools.github.configure',
    'tools.github.authorize.start', 'tools.github.authorize.poll',
    'tools.github.authorize.cancel', 'sessions.github.publish',
    'diagnostics.lanes', 'session.members.listEvidence', 'plugins.inspect',
  };

  static const events = <String>{
    'connect.challenge', 'agent', 'chat', 'chat.metadata.changed', 'ui.command',
    'session.approval', 'session.message', 'session.observer', 'session.operation',
    'session.sharing', 'session.sharing.evidence', 'session.suggestion',
    'session.typing', 'session.tool', 'sessions.changed',
    'controlUi.sessionPullRequests.changed', 'presence', 'tick', 'talk.mode',
    'talk.event', 'shutdown', 'health', 'heartbeat', 'cron', 'task',
    'task.suggestion', 'node.pair.requested', 'node.pair.resolved', 'node.presence',
    'node.runnerInventory.changed', 'node.invoke.cancel', 'node.invoke.input',
    'node.invoke.request', 'device.pair.changed', 'device.pair.requested',
    'device.pair.resolved', 'device.pair.setup.completed',
    'device.pair.setup.deliveryUncertain', 'users.prefs.changed', 'skills.changed',
    'voicewake.changed', 'voicewake.routing.changed', 'exec.approval.requested',
    'exec.approval.resolved', 'question.requested', 'question.resolved',
    'plugin.approval.requested', 'plugin.approval.resolved',
    'openclaw.approval.requested', 'openclaw.approval.resolved', 'terminal.data',
    'terminal.exit', 'update.available', 'portal.changed', 'progressCard.changed',
  };

  static bool supportsMethod(String method) => methods.contains(method);
  static bool supportsEvent(String event) => events.contains(event);
}
