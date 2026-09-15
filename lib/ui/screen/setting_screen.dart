import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/screen/index_screen.dart';
import 'package:parrot_app/ui/view_model/setting_viewmodel.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:parrot_app/util/tts_voice_util.dart';
import 'package:provider/provider.dart';

class SettingScreen extends StatefulWidget {
  final SettingViewmodel viewmodel;

  const SettingScreen({super.key, required this.viewmodel});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool isCurrentLanguageInstalled = false;

  /// 音色列表只拉一次：切换语言/音量只是重新过滤，不必每次 build 都走网络。
  Future<dynamic>? _voicesFuture;

  /// 下拉框的 value 是稳定字符串 key（[TtsVoiceUtil.keyOf]），这里反查回
  /// Edge 的音色名（shortName）交给 setVoice。
  final Map<String, String> _voiceNameByKey = {};

  @override
  void dispose() {
    widget.viewmodel.saveSetting();
    super.dispose();
  }

  Future<dynamic> _getLanguages() async =>
      await widget.viewmodel.getLanguages();

  Future<dynamic> _getVoices() =>
      _voicesFuture ??= widget.viewmodel.getVoices();

  /// Edge 音色名就是 [TtsVoiceUtil.keyOf] 取到的 identifier（见
  /// `EdgeTTSUtil.voiceToMap`），退一步才用 name。
  static String _voiceNameOf(Map<String, String> voice) {
    final identifier = voice['identifier'];
    if (identifier != null && identifier.isNotEmpty) return identifier;
    return voice['name'] ?? '';
  }

  List<DropdownMenuItem<String>> _buildVoiceItems(dynamic rawVoices) {
    final visible = TtsVoiceUtil.visibleVoices(
      voices: TtsVoiceUtil.parseVoices(rawVoices),
      language: widget.viewmodel.settingRepository.language,
      selected: _selectedVoiceMap(),
    );

    _voiceNameByKey.clear();
    final items = <DropdownMenuItem<String>>[];
    for (final voice in visible) {
      final key = TtsVoiceUtil.keyOf(voice);
      _voiceNameByKey[key] = _voiceNameOf(voice);
      items.add(
        DropdownMenuItem<String>(
          value: key,
          child: Text(
            TtsVoiceUtil.labelOf(voice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return items;
  }

  /// 已保存音色的 map 形态（`visibleVoices` 需要它保证选中项一定在列表里）。
  ///
  /// 仓库只存 shortName，而 Edge 音色的 identifier 恰好就是它，
  /// 所以这里补出来的 key 和列表里真实音色的 key 一致。
  Map<String, String>? _selectedVoiceMap() {
    final voice = widget.viewmodel.settingRepository.voice;
    if (voice == null) return null;
    return {'name': voice, 'identifier': voice};
  }

  void changedVoiceDropDownItem(String? voiceKey) {
    if (voiceKey == null) return;
    final voice = _voiceNameByKey[voiceKey];
    if (voice == null || voice.isEmpty) return;
    setState(() {
      widget.viewmodel.setVoice(voice);
    });
  }

  List<DropdownMenuItem<String>> getLanguageDropDownMenuItems(
    dynamic languages,
  ) {
    final items = <DropdownMenuItem<String>>[];
    final seenLanguages = <String>{};
    for (final language in languages) {
      final value = language.toString();
      if (seenLanguages.add(value)) {
        items.add(
          DropdownMenuItem<String>(
            value: value,
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      }
    }
    return items;
  }

  Future<void> changedLanguageDropDownItem(dynamic selectLanguage) async {
    final language = selectLanguage?.toString();
    if (language == null) return;
    await widget.viewmodel.setLanguage(language);
    // Edge 里语言是由音色决定的，切语言可能连带换音色，
    // 等仓储落定后再刷一次，否则音色下拉框还停在被替换掉的旧音色上。
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '打开侧边栏',
          onPressed: () => indexController.switchSideBarVisible(),
        ),
        title: const Text('设置'),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: ListenableBuilder(
          listenable: context.read<SettingRepository>(),
          builder: (context, child) {
            final selectedServer =
                context.watch<ServerRepository>().selectedServer;
            final isLocalGateway =
                Platform.isMacOS || Platform.isWindows
                    ? selectedServer != null &&
                        ServerConfig.isLoopbackHost(selectedServer.host)
                    : false;
            return Column(
              children: [
                // if (isLocalGateway)
                //   Card(
                //     margin: const EdgeInsets.all(10),
                //     child: _buildGatewayControl(),
                //   ),
                Card(
                  margin: const EdgeInsets.all(10),
                  child: _buildTtsSetting(),
                ),
                if (!widget.viewmodel.settingRepository.isOpenclawTTS)
                  Card(
                    margin: const EdgeInsets.all(10),
                    child: _buildSliders(),
                  ),
                // Card(
                //   margin: const EdgeInsets.all(10),
                //   child: _buildModelConfig(),
                // ),
                Card(margin: const EdgeInsets.all(10), child: _buildMore()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTtsSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('对话中说话打断语音', style: TextStyle(fontSize: 12)),
          subtitle: const Text(
            '建议支持AEC设备或连接耳机使用',
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
          trailing: Switch(
            value: widget.viewmodel.settingRepository.isTTSAbort,
            onChanged: (v) => widget.viewmodel.setTTSAbort(v),
          ),
        ),
        if (Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isWindows)
          ListTile(
            title: const Text('使用Openclaw TTS', style: TextStyle(fontSize: 12)),
            subtitle: const Text(
              '需要先配置OpenClaw的TTS',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
            trailing: Switch(
              value: widget.viewmodel.settingRepository.isOpenclawTTS,
              onChanged: (v) => widget.viewmodel.setOpenclawTTS(v),
            ),
          ),
      ],
    );
  }

  // Edge 没有「引擎」这个概念：服务端里音色就是引擎，
  // 所以原来那组 getEngines/setEngine 的下拉框已经去掉。

  Widget _language() => ListTile(
    leading: const Text("语言"),
    trailing: SizedBox(
      width: 150,
      child: FutureBuilder<dynamic>(
        future: _getLanguages(),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData) {
            final items = getLanguageDropDownMenuItems(snapshot.data);
            final language = widget.viewmodel.settingRepository.language;
            final selectedLanguage =
                items.any((item) => item.value == language) ? language : null;
            return DropdownButton<String>(
              isExpanded: true,
              value: selectedLanguage,
              items: items,
              onChanged: changedLanguageDropDownItem,
            );
          } else if (snapshot.hasError) {
            return const SizedBox.shrink();
          }
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  Widget _voice() {
    return ListTile(
      leading: const Text("音色"),
      trailing: SizedBox(
        width: 190,
        child: FutureBuilder<dynamic>(
          future: _getVoices(),
          builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (snapshot.hasError) {
              return const Text(
                '不可用',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              );
            }
            final items = _buildVoiceItems(snapshot.data);
            if (items.isEmpty) {
              return const Text(
                '无可用音色',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              );
            }
            final voice = widget.viewmodel.settingRepository.voice;
            // 保存的音色可能已从服务端下架，此时按「默认」展示，避免断言崩溃。
            final selected =
                items.any((item) => item.value == voice) ? voice : null;
            return DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: const Text(
                '默认',
                style: TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              items: items,
              onChanged: changedVoiceDropDownItem,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSliders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_language(), _voice(), _volume(), _pitch(), _rate()],
    );
  }

  Widget _volume() {
    return ListTile(
      leading: Text("音量"),
      trailing: DropdownButton<double>(
        value: widget.viewmodel.settingRepository.volume,
        items: [
          DropdownMenuItem(value: 1.0, child: Text("最大")),
          DropdownMenuItem(value: 0.5, child: Text("正常")),
          DropdownMenuItem(value: 0, child: Text("禁音")),
        ],
        onChanged: (v) {
          widget.viewmodel.setVolume(v!);
          setState(() {});
        },
      ),
    );
  }

  Widget _pitch() {
    return ListTile(
      leading: Text("音调"),
      trailing: DropdownButton<double>(
        // Edge 的音调是 Hz 偏移，档位取官方 example 的音调滑杆两端（-5~5 × 20）。
        value: widget.viewmodel.settingRepository.pitch,
        items: [
          DropdownMenuItem(value: EdgeTTSUtil.maxPitch, child: Text("最高")),
          DropdownMenuItem(value: 0, child: Text("正常")),
          DropdownMenuItem(value: EdgeTTSUtil.minPitch, child: Text("最低")),
        ],
        onChanged: (v) {
          widget.viewmodel.setPitch(v!);
          setState(() {});
        },
      ),
    );
  }

  Widget _rate() {
    return ListTile(
      leading: Text("速度"),
      trailing: DropdownButton<double>(
        // Edge 的语速是倍率，1.0 为正常（对齐官方 example 的 Speed 滑杆范围）。
        value: widget.viewmodel.settingRepository.rate,
        items: [
          DropdownMenuItem(value: EdgeTTSUtil.maxRate, child: Text("最快")),
          DropdownMenuItem(value: 1.0, child: Text("正常")),
          DropdownMenuItem(value: EdgeTTSUtil.minRate, child: Text("最慢")),
        ],
        onChanged: (v) {
          widget.viewmodel.setSpeechRate(v!);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildGatewayControl() {
    return ListTile(
      title: const Text('OpenClaw Gateway', style: TextStyle(fontSize: 12)),
      subtitle: const Text(
        '查看状态并启动或关闭本机网关',
        style: TextStyle(color: Colors.grey, fontSize: 10),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push(Routes.gatewayControl),
    );
  }

  Widget _buildModelConfig() {
    return ListTile(
      // leading: const Icon(Icons.psychology_outlined, size: 20),
      title: const Text('模型配置', style: TextStyle(fontSize: 12)),
      subtitle: const Text(
        '查看和添加 OpenClaw 模型',
        style: TextStyle(color: Colors.grey, fontSize: 10),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push(Routes.modelList),
    );
  }

  Widget _buildMore() {
    return ListTile(
      title: const Text('使用指南', style: TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push(Routes.help),
    );
  }
}
