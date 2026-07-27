import 'package:flutter/cupertino.dart';
import 'package:parrot_app/data/repository/setting_repository.dart';
import 'package:parrot_app/util/flutter_tts_util.dart';

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

  Future<dynamic> switchSpeaker() async {
    _settingRepository.switchSpeaker();
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

  Future<dynamic> getEngines() async {
    return _settingRepository.getEngines();
  }

  Future<dynamic> setEngine(dynamic selectedEngine) async {
    return _settingRepository.setEngine(selectedEngine);
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
