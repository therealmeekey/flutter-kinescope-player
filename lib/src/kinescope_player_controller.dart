// Copyright (c) 2021-present, Kinescope
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// ignore_for_file: member-ordering-extended
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_kinescope_sdk/src/data/player_parameters.dart';
import 'package:flutter_kinescope_sdk/src/data/player_status.dart';
import 'package:flutter_kinescope_sdk/src/utils/uri_builder.dart';

/// Controls a Kinescope player, and provides status updates using [status] stream.
///
/// The video is displayed in a Flutter app by creating a `KinescopePlayer` widget.
class KinescopePlayerController {
  String _videoId;

  /// Initial `KinescopePlayer` parameters.
  final PlayerParameters parameters;

  /// StreamController for [status] stream.
  final statusController = StreamController<KinescopePlayerStatus>();

  final playbackRateController =
      StreamController<double>(); // Stream для скорости
  Timer? _playbackRateTimer; // Таймер для скорости
  Stream<double> get playbackRate =>
      playbackRateController.stream; // Stream скорости
  /// Controller to communicate with WebView.
  late InAppWebViewController webViewController;

  /// [Completer] for [getCurrentTime] method
  Completer<Duration>? getCurrentTimeCompleter;

  /// [Completer] for [getDuration] method
  Completer<Duration>? getDurationCompleter;

  Completer<double>? getPlaybackRateCompleter;

  /// [Stream], that provides current player status
  Stream<KinescopePlayerStatus> get status => statusController.stream;

  void Function(bool)? onChangeFullscreen;

  /// Currently playing video id
  String get videoId => _videoId;

  KinescopePlayerController(
    /// The video id with which the player initializes.
    String videoId, {
    this.parameters = const PlayerParameters(),
    this.onChangeFullscreen,
  }) : _videoId = videoId;

  /// Loads the video as per the [videoId] provided.
  void load(String videoId) {
    statusController.sink.add(KinescopePlayerStatus.unknown);
    webViewController.evaluateJavascript(
      source: 'loadVideo("${UriBuilder.buildVideoUri(videoId: videoId)}");',
    );

    _videoId = videoId;
  }

  /// Plays the video.
  void play() {
    webViewController.evaluateJavascript(source: 'play();');
  }

  /// Pauses the video.
  void pause() {
    webViewController.evaluateJavascript(source: 'pause();');
  }

  /// Stops the video.
  void stop() {
    webViewController.evaluateJavascript(source: 'stop();');
  }

  /// Get current position.
  Future<Duration> getCurrentTime() async {
    getCurrentTimeCompleter = Completer<Duration>();

    await webViewController.evaluateJavascript(
      source: 'getCurrentTime();',
    );

    final time = await getCurrentTimeCompleter?.future;

    return time ?? Duration.zero;
  }

  /// Get duration of video.
  Future<Duration> getDuration() async {
    getDurationCompleter = Completer<Duration>();

    await webViewController.evaluateJavascript(
      source: 'getDuration();',
    );

    final duration = await getDurationCompleter?.future;

    return duration ?? Duration.zero;
  }

  /// Seek to any position.
  void seekTo(Duration duration) {
    webViewController.evaluateJavascript(
      source: 'seekTo(${duration.inSeconds});',
    );
  }

  /// Set volume level
  /// (0..1, where 0 is 0% and 1 is 100%)
  /// Works only on Android
  void setVolume(double value) {
    if (value > 0 || value <= 1) {
      webViewController.evaluateJavascript(source: 'setVolume($value);');
    }
  }

  /// Запускаем обновления текущей скорости видео
  void startPlaybackRateUpdates() {
    double previousPlaybackRate = 1;
    _playbackRateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final playbackRate = await getPlaybackRate();
        if (previousPlaybackRate != playbackRate) {
          previousPlaybackRate = playbackRate;
          playbackRateController.add(playbackRate);
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error updating playback rate: $e");
        }
      }
    });
  }

  void stopPlaybackRateUpdates() {
    _playbackRateTimer?.cancel();
    _playbackRateTimer = null;
  }

  Future<double> getPlaybackRate() async {
    getPlaybackRateCompleter = Completer<double>();

    await webViewController.evaluateJavascript(
      source: 'getPlaybackRate();',
    );

    final playbackRate = await getPlaybackRateCompleter?.future;
    return playbackRate ?? 1.0;
  }

  /// Mutes the player.
  void mute() {
    webViewController.evaluateJavascript(source: 'mute();');
  }

  /// Unmutes the player.
  void unmute() {
    webViewController.evaluateJavascript(source: 'unmute();');
  }

  /// Close [statusController]
  void dispose() {
    stopPlaybackRateUpdates();
    statusController.close();
    playbackRateController.close();
  }
}
