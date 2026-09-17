import 'package:flutter/cupertino.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';

class SettingViewmodel extends ChangeNotifier {
  SettingRepository _settingRepository;

  SettingRepository get settingRepository => _settingRepository;

  SettingViewmodel({required SettingRepository settingRepository})
    : _settingRepository = settingRepository;

  Future<dynamic> setTTSAbort(bool isTTSAbort) async {
    _settingRepository.setTTSAbort(isTTSAbort);
  }

  Future<dynamic> setOpenclawTTS(bool isOpenclawTTS) async {
    _settingRepository.setOpenclawTTS(isOpenclawTTS);
  }

  Future<dynamic> switchVoicePlay() async {
    _settingRepository.switchVoicePlay();
  }

  Future<dynamic> switchShowFace() async {
    _settingRepository.switchShowFace();
  }

  Future<dynamic> saveSetting() async {
    _settingRepository.saveSetting();
  }

  Future<dynamic> getLanguages() async {
    return _settingRepository.getLanguages();
  }

  Future<dynamic> getVoices() async {
    return _settingRepository.getVoices();
  }

  /// [voice] 是 Edge 音色的 shortName（如 `zh-CN-YunyangNeural`）。
  Future<dynamic> setVoice(String voice) async {
    return _settingRepository.setVoice(voice);
  }

  Future<dynamic> setLanguage(dynamic selectLanguage) async {
    return _settingRepository.setLanguage(selectLanguage);
  }

  Future<dynamic> setVolume(double v) async {
    return _settingRepository.setVolume(v);
  }

  Future<dynamic> setPitch(double v) async {
    return _settingRepository.setPitch(v);
  }

  Future<dynamic> setSpeechRate(double v) async {
    return _settingRepository.setSpeechRate(v);
  }
}
