import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/util/edge_tts_util.dart';
import 'package:parrot_app/util/tts_voice_util.dart';

class SettingRepository extends ChangeNotifier {
  final SharedPreferencesService _preferencesService;

  /// 本地 TTS 统一走 Edge 在线合成（语音页、聊天页的朗读都是它），
  /// 所以这里不再持有 flutter_tts 的实例。
  final EdgeTTSUtil _edgeTts = EdgeTTSUtil();

  bool _isOpenclawTTS = true;
  bool _isTTSAbort = false;

  bool get isTTSAbort => _isTTSAbort;

  bool get isOpenclawTTS => _isOpenclawTTS;

  double _volume = 1.0;

  /// 音调偏移，单位 Hz（`0` 为原始音高，区间见 [EdgeTTSUtil.minPitch]）。
  double _pitch = 0;

  /// 语速倍率，`1.0` 为正常语速（区间见 [EdgeTTSUtil.minRate]）。
  double _rate = 1.0;

  String? _language = EdgeTTSUtil.defaultLocale;

  /// 选中的音色 shortName（如 `zh-CN-YunyangNeural`），
  /// null 表示跟随语言用默认音色。
  String? _voice;

  double get volume => _volume;

  double get pitch => _pitch;

  double get rate => _rate;

  String? get language => _language;

  String? get voice => _voice;

  bool _isSpeakerOn = false;
  bool _isShowFace = false;

  bool get isSpeakerOn => _isSpeakerOn;

  bool get isShowFace => _isShowFace;

  SettingRepository({required SharedPreferencesService preferencesService})
    : _preferencesService = preferencesService {
    _isTTSAbort = _preferencesService.getIsTTSAbort();
    _isOpenclawTTS = _preferencesService.getIsOpenclawTTS();
    _isSpeakerOn = _preferencesService.getIsSpeakerOn();
    _isShowFace = _preferencesService.getIsShowFace();
    _restoreSetting();
  }

  /// 从本地存储恢复 TTS 参数。
  ///
  /// 旧版本存的是 flutter_tts 的数值（音调 0.5~2.0、语速 0~1.0），语义和 Edge
  /// 不同，所以换过存储 key（见 [SharedPreferencesService]），这里读到的只可能是
  /// Edge 的值。解析失败时保留默认值，不能让一份坏数据把启动流程打挂。
  void _restoreSetting() {
    final settingString = _preferencesService.getEdgeTTSSetting();
    if (settingString == null) return;
    try {
      final setting = jsonDecode(settingString);
      if (setting is! Map) return;
      final volume = setting['volume'];
      if (volume is num) _volume = volume.toDouble();
      final pitch = setting['pitch'];
      if (pitch is num) _pitch = pitch.toDouble();
      final rate = setting['rate'];
      if (rate is num) _rate = rate.toDouble();
      final language = setting['language'];
      if (language is String && language.isNotEmpty) _language = language;
      final voice = setting['voice'];
      if (voice is String && voice.isNotEmpty) _voice = voice;
    } on FormatException catch (error) {
      debugPrint('读取本地 TTS 设置失败，改用默认值: $error');
    }
  }

  void setTTSAbort(bool isTTSAbort) {
    _isTTSAbort = isTTSAbort;
    _preferencesService.saveIsTTSAbort(isTTSAbort);
    notifyListeners();
  }

  void setOpenclawTTS(bool isOpenclawTTS) {
    _isOpenclawTTS = isOpenclawTTS;
    _preferencesService.saveIsOpenclawTTSKey(isOpenclawTTS);
    notifyListeners();
  }

  bool switchSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _preferencesService.saveIsSpeakerOn(_isSpeakerOn);
    notifyListeners();
    return _isSpeakerOn;
  }

  void switchShowFace() {
    _isShowFace = !_isShowFace;
    _preferencesService.saveIsShowFace(_isShowFace);
    notifyListeners();
  }

  void saveSetting() {
    final dynamic ttsSetting = {
      'volume': _volume,
      'pitch': _pitch,
      'rate': _rate,
      'language': _language,
      'voice': _voice,
    };
    _preferencesService.saveEdgeTTSSetting(jsonEncode(ttsSetting));
  }

  /// 把已保存的 TTS 参数应用到 Edge。
  ///
  /// 设置页的改动只在当次会话生效，App 启动时得补这一步，
  /// 否则重启后 Edge 会回到默认音色和默认语速。
  void applySavedSetting() {
    _edgeTts
      ..setVolume(_volume)
      ..setPitch(_pitch)
      ..setSpeechRate(_rate);
    final voice = _voice;
    if (voice != null) {
      // 换音色会清掉显式指定的 locale，让 SSML 从音色名重新推断语言，正合适。
      _edgeTts.setVoice(voice);
    } else if (_language != null) {
      _edgeTts.setLanguage(_language);
    }
  }

  /// 音色覆盖的语言（locale，如 `zh-CN`）列表。
  Future<dynamic> getLanguages() async {
    return _edgeTts.getLanguages();
  }

  /// 返回可用的音色列表，元素形如 `{name, locale, gender, identifier}`。
  ///
  /// 这里让失败抛出去：页面要能区分「拉取失败」和「确实一个音色都没有」，
  /// 前者提示「不可用」，后者提示「无可用音色」。
  Future<dynamic> getVoices() async {
    return _edgeTts.getVoiceMaps(throwOnError: true);
  }

  Future<dynamic> setVoice(String voice) async {
    _voice = voice;
    _edgeTts.setVoice(voice);
  }

  Future<dynamic> setLanguage(dynamic selectLanguage) async {
    final language = selectLanguage?.toString();
    _language = language;
    _edgeTts.setLanguage(language);
    await _syncVoiceWithLanguage(language);
  }

  /// Edge 里「语言」是由音色决定的，[EdgeTTSUtil.setLanguage] 只改 SSML 的
  /// `xml:lang`、不会换音色。当前音色不属于新语言时自动挑一个，
  /// 否则用户切了语言却听不出任何变化。
  Future<void> _syncVoiceWithLanguage(String? language) async {
    if (language == null || language.isEmpty) return;
    final current = _voice;
    if (current != null) {
      final locale = await _localeOfVoice(current);
      if (locale != null && TtsVoiceUtil.localeMatches(locale, language)) return;
    }
    final picked = await _edgeTts.pickVoiceForLocale(language);
    if (picked != null) setVoice(picked);
  }

  /// 从音色目录反查某个音色的 locale（走 [EdgeTTSUtil] 的缓存，不额外发请求）。
  Future<String?> _localeOfVoice(String voice) async {
    final voices = await _edgeTts.getVoiceMaps();
    for (final item in voices) {
      if (item['name'] == voice) return item['locale'];
    }
    return null;
  }

  Future<dynamic> setVolume(double v) async {
    _volume = v;
    _edgeTts.setVolume(v);
  }

  Future<dynamic> setPitch(double v) async {
    _pitch = v;
    _edgeTts.setPitch(v);
  }

  Future<dynamic> setSpeechRate(double v) async {
    _rate = v;
    _edgeTts.setSpeechRate(v);
  }
}
