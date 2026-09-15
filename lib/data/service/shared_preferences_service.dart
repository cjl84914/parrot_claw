// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  final SharedPreferences _prefs;

  SharedPreferencesService(this._prefs);

  final _isTTSAbortKey = 'isTTSAbort';
  final _isOpenclawTTSKey = 'isOpenclawTTS';
  final _isSpeakerOnKey = 'isSpeakerOn';
  final _isShowFaceKey = 'isShowFace';

  /// 本地 TTS 参数（音色/语速/音调/音量）。
  ///
  /// 特意没有沿用旧的 `_flutterTTS` key：那套数值是 flutter_tts 的语义
  /// （音调 0.5~2.0、语速 0~1.0），直接读进来当 Edge 的 Hz / 倍率用会跑偏，
  /// 换新 key 等于自动丢弃旧值、回到默认。
  final _edgeTTSKey = '_edgeTTS';

  bool getIsTTSAbort() => _prefs.getBool(_isTTSAbortKey) ?? false;

  Future<bool> saveIsTTSAbort(bool v) => _prefs.setBool(_isTTSAbortKey, v);

  bool getIsOpenclawTTS() => _prefs.getBool(_isOpenclawTTSKey) ?? false;

  Future<bool> saveIsOpenclawTTSKey(bool v) =>
      _prefs.setBool(_isOpenclawTTSKey, v);

  String? getEdgeTTSSetting() => _prefs.getString(_edgeTTSKey);

  Future<bool> saveEdgeTTSSetting(String v) =>
      _prefs.setString(_edgeTTSKey, v);

  bool getIsSpeakerOn() => _prefs.getBool(_isSpeakerOnKey) ?? false;

  Future<bool> saveIsSpeakerOn(bool v) => _prefs.setBool(_isSpeakerOnKey, v);

  bool getIsShowFace() => _prefs.getBool(_isShowFaceKey) ?? false;

  Future<bool> saveIsShowFace(bool v) => _prefs.setBool(_isShowFaceKey, v);
}
