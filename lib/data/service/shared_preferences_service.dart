// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:parrot_app/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  final SharedPreferences _prefs;

  SharedPreferencesService(this._prefs);

  final _isTTSAbortKey = 'isTTSAbort';
  final _isOpenclawTTSKey = 'isOpenclawTTS';
  final _isSpeakerOnKey = 'isSpeakerOn';
  final _isShowFaceKey = 'isShowFace';
  final _flutterTTSKey = '_flutterTTS';

  final _log = Logger('SharedPreferencesService');

  bool getIsTTSAbort() => _prefs.getBool(_isTTSAbortKey) ?? false;

  Future<bool> saveIsTTSAbort(bool v) => _prefs.setBool(_isTTSAbortKey, v);

  bool getIsOpenclawTTS() => _prefs.getBool(_isOpenclawTTSKey) ?? false ;

  Future<bool> saveIsOpenclawTTSKey(bool v) =>
      _prefs.setBool(_isOpenclawTTSKey, v);

  String? getFlutterTTSSetting() => _prefs.getString(_flutterTTSKey);

  Future<bool> saveFlutterTTSSetting(String v) =>
      _prefs.setString(_flutterTTSKey, v);

  bool getIsSpeakerOn() => _prefs.getBool(_isSpeakerOnKey) ?? false;

  Future<bool> saveIsSpeakerOn(bool v) => _prefs.setBool(_isSpeakerOnKey, v);

  bool getIsShowFace() => _prefs.getBool(_isShowFaceKey) ?? false;

  Future<bool> saveIsShowFace(bool v) => _prefs.setBool(_isShowFaceKey, v);
}
