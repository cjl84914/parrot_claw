import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parrot_app/data/model/server_config.dart';
import 'package:parrot_app/data/repository/server_repository.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/main.dart';
import 'package:parrot_app/ui/view_model/setting_viewmodel.dart';
import 'package:provider/provider.dart';

class SettingScreen extends StatefulWidget {
  final SettingViewmodel viewmodel;

  const SettingScreen({super.key, required this.viewmodel});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool isCurrentLanguageInstalled = false;

  @override
  void dispose() {
    widget.viewmodel.saveSetting();
    super.dispose();
  }

  Future<dynamic> _getLanguages() async =>
      await widget.viewmodel.getLanguages();

  Future<dynamic> _getEngines() async => await widget.viewmodel.getEngines();

  List<DropdownMenuItem<String>> getEnginesDropDownMenuItems(dynamic engines) {
    var items = <DropdownMenuItem<String>>[];
    for (String type in engines) {
      items.add(
        DropdownMenuItem(
          value: type,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(type, maxLines: 1),
          ),
        ),
      );
    }
    return items;
  }

  void changedEnginesDropDownItem(dynamic selectedEngine) async {
    setState(() {
      widget.viewmodel.setEngine(selectedEngine.toString());
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

  void changedLanguageDropDownItem(dynamic selectLanguage) {
    setState(() {
      widget.viewmodel.setLanguage(selectLanguage.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                if (isLocalGateway)
                  Card(
                    margin: const EdgeInsets.all(10),
                    child: _buildGatewayControl(),
                  ),
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

  // Widget _enginesDropDownSection(dynamic engines) => ListTile(
  //       leading: Text("voice_engine"),
  //       title: Container(
  //           alignment: Alignment.centerRight,
  //           child: DropdownButton(
  //             value: widget.viewmodel.engine,
  //             items: getEnginesDropDownMenuItems(engines),
  //             onChanged: changedEnginesDropDownItem,
  //           )),
  //     );

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

  Widget _buildSliders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_language(), _volume(), _pitch(), _rate()],
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
        value: widget.viewmodel.settingRepository.pitch,
        items: [
          DropdownMenuItem(value: 2.0, child: Text("最高")),
          DropdownMenuItem(value: 1.0, child: Text("正常")),
          DropdownMenuItem(value: 0.5, child: Text("最低")),
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
        value: widget.viewmodel.settingRepository.rate,
        items: [
          DropdownMenuItem(value: 1.0, child: Text("最快")),
          DropdownMenuItem(value: 0.5, child: Text("正常")),
          DropdownMenuItem(value: 0.0, child: Text("最慢")),
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
      title: const Text('更多', style: TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push(Routes.more),
    );
  }
}
