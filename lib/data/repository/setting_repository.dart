import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:parrot_app/data/service/shared_preferences_service.dart';
import 'package:parrot_app/util/flutter_tts_util.dart';

class SettingRepository extends ChangeNotifier {
  final SharedPreferencesService _preferencesService;
  final FlutterTTSUtil _flutterTTSUtil = FlutterTTSUtil();

  bool _isOpenclawTTS = true;
  bool _isTTSAbort = false;

  bool get isTTSAbort => _isTTSAbort;

  bool get isOpenclawTTS => _isOpenclawTTS;

  double _volume = 1.0;
  double _pitch = 0.5;
  double _rate = 0.5;
  String? _language;
  String? _engine;

  double get volume => _volume;

  double get pitch => _pitch;

  double get rate => _rate;

  String? get language => _language;

  String? get engine => _engine;

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
    _language = ui.window.locale.languageCode;
    final settingString = _preferencesService.getFlutterTTSSetting();
    if (settingString != null) {
      final setting = jsonDecode(settingString);
      _language = setting['language'];
      _volume = setting['volume'];
      _pitch = setting['pitch'];
      _rate = setting['rate'];
      _engine = setting['engine'];
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
      'engine': _engine,
    };
    _preferencesService.saveFlutterTTSSetting(jsonEncode(ttsSetting));
  }

  Future<dynamic> getLanguages() async {
    return _flutterTTSUtil.getLanguages();
  }

  Future<dynamic> getEngines() async {
    return _flutterTTSUtil.getEngines();
  }

  Future<dynamic> setEngine(dynamic selectedEngine) async {
    _engine = selectedEngine;
    return _flutterTTSUtil.setEngine(selectedEngine);
  }

  Future<dynamic> setLanguage(dynamic selectLanguage) async {
    _language = selectLanguage;
    return _flutterTTSUtil.setLanguage(selectLanguage);
  }

  Future<dynamic> setVolume(double v) async {
    _volume = v;
    return _flutterTTSUtil.setVolume(v);
  }

  Future<dynamic> setPitch(double v) async {
    _pitch = v;
    return _flutterTTSUtil.setPitch(v);
  }

  Future<dynamic> setSpeechRate(double v) async {
    _rate = v;
    return _flutterTTSUtil.setSpeechRate(v);
  }
}
