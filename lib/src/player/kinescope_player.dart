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

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/player_status.dart';
import '../kinescope_player_controller.dart';
import '../utils/uri_builder.dart';

const _scheme = 'https';
const _kinescopeUri = 'kinescope.io';

/// A widget to play or stream Kinescope videos using the official embedded API
///
/// Using [KinescopePlayer] widget:
///
/// ```dart
/// KinescopePlayer(
///   controller: KinescopePlayerController(
///     yourVideoId,
///     parameters: const PlayerParameters(
///       autoplay: true,
///       muted: true,
///       loop: true,
///     ),
///   ),
///   aspectRatio: 16 / 10,
/// )
/// ```
class KinescopePlayer extends StatefulWidget {
  /// The [controller] for this player.
  final KinescopePlayerController controller;

  /// Aspect ratio for the player,
  /// by default it's 16 / 9.
  final double aspectRatio;
  final bool useCustomFullscreen;

  /// A widget to play Kinescope videos.
  const KinescopePlayer({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.useCustomFullscreen = false,
  });

  @override
  _KinescopePlayerState createState() => _KinescopePlayerState();
}

class _KinescopePlayerState extends State<KinescopePlayer> {
  late String videoId;
  late String externalId;
  late String baseUrl;
  final GlobalKey _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    videoId = widget.controller.videoId;
    externalId = widget.controller.parameters.externalId ?? '';
    baseUrl = widget.controller.parameters.baseUrl ??
        Uri(
          scheme: _scheme,
          host: _kinescopeUri,
        ).toString();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: InAppWebView(
        key: _webViewKey,
        onWebViewCreated: (controller) {
          widget.controller.webViewController = controller;
          controller
            ..addJavaScriptHandler(
              handlerName: 'events',
              callback: (args) {
                final event = (args.first as String).toLowerCase();

                widget.controller.statusController.add(
                  KinescopePlayerStatus.values.firstWhere(
                    (value) => value.toString() == event,
                    orElse: () => KinescopePlayerStatus.unknown,
                  ),
                );
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'getCurrentTimeResult',
              callback: (args) {
                final dynamic seconds = args.first;
                if (seconds is num) {
                  if (widget.controller.getCurrentTimeCompleter != null &&
                      !widget.controller.getCurrentTimeCompleter!.isCompleted) {
                    widget.controller.getCurrentTimeCompleter?.complete(
                      Duration(milliseconds: (seconds * 1000).ceil()),
                    );
                    widget.controller.getCurrentTimeCompleter = null;
                  }
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'isPaused',
              callback: (args) {
                final dynamic isPaused = args.first;
                if (isPaused is bool) {
                  widget.controller.getIsPausedCompleter?.complete(isPaused);
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'getPlaybackRateResult',
              callback: (args) {
                final dynamic currentSpeed = args.first;
                if (currentSpeed is num) {
                  widget.controller.getPlaybackRateCompleter
                      ?.complete(currentSpeed.toDouble());
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'playbackRateEvent',
              callback: (args) async {
                final dynamic currentSpeed = args.first;
                if (currentSpeed is num) {
                  widget.controller.onChangePlaybackRate
                      ?.call(currentSpeed.toDouble());
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'progressChangeEvent',
              callback: (args) async {
                final dynamic progress = args.first;
                if (progress is num) {
                  widget.controller.onChangeProgress?.call(progress.toDouble());
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'onChangeFullscreen',
              callback: (args) {
                final bool isFullscreen = args.first;
                widget.controller.onChangeFullscreen?.call(isFullscreen);
                changeSizeToDefault();
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'pipChangeEvent',
              callback: (args) {
                final bool isPip = args.first;
                widget.controller.onChangePip?.call(isPip);
                changeSizeToDefault();
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'getDurationResult',
              callback: (args) {
                final dynamic seconds = args.first;
                if (seconds is num) {
                  if (widget.controller.getDurationCompleter != null &&
                      !widget.controller.getDurationCompleter!.isCompleted) {
                    widget.controller.getDurationCompleter?.complete(
                      Duration(milliseconds: (seconds * 1000).ceil()),
                    );
                  }
                }
              },
            );
        },
        initialSettings: InAppWebViewSettings(
          iframeAllowFullscreen: true,
          useShouldInterceptRequest: true,
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          disableContextMenu: true,
          supportZoom: false,
          userAgent: widget.controller.parameters.userAgent ?? getUserArgent(),
          allowsInlineMediaPlayback: true,
          allowsBackForwardNavigationGestures: false,
        ),
        onPermissionRequest: (controller, permissionRequest) async {
          return PermissionResponse(
            resources: [PermissionResourceType.PROTECTED_MEDIA_ID],
            action: PermissionResponseAction.GRANT,
          );
        },
        onNavigationResponse: (_, navigationResponse) async {
          if (navigationResponse.response!.url!.host == _kinescopeUri) {
            return NavigationResponseAction.ALLOW;
          }
          return NavigationResponseAction.CANCEL;
        },
        shouldOverrideUrlLoading: (_, __) async => Platform.isIOS
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL,
        onConsoleMessage: (_, consoleMessage) {
          debugPrint('js: ${consoleMessage.message}');
        },
        initialData: InAppWebViewInitialData(
          data: _player,
          baseUrl: WebUri(baseUrl),
        ),
      ),
    );
  }

  void changeSizeToDefault() {
    widget.controller.webViewController.evaluateJavascript(
      source: "document.getElementById('player').style.height = '100%';",
    );
    widget.controller.webViewController.evaluateJavascript(
      source: "document.getElementById('player').style.width = '100%';",
    );
  }

  String? getUserArgent() {
    if (kIsWeb) {
      return null;
    }

    return (Platform.isIOS
        ? 'Mozilla/5.0 (iPad; CPU iPhone OS 13_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) KinescopePlayerFlutter/0.1.10'
        : 'Mozilla/5.0 (Android 9.0; Mobile; rv:59.0) Gecko/59.0 Firefox/59.0 KinescopePlayerFlutter/0.1.10');
  }

  // ignore: member-ordering-extended
  String get _player => '''
  <!DOCTYPE html>
  <html>
  
  <head>
      <meta charset="utf-8" />
      <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>
      <style>
        html, body {
            padding: 0;
            margin: 0;
            width: 100%;
            height: 100%;
        }
          #player {
            position: fixed;
            left: 0;
            width: 100vw;
            height: 100vh;
            object-fit: cover;
            margin: 0;  /* Убирает отступы */
            padding: 0; /* Убирает внутренние отступы */
          }
      </style>
  
      <script>
          window.addEventListener("flutterInAppWebViewPlatformReady", function (event) {
              window.flutter_inappwebview.callHandler('events', 'ready');
          });
  
          let kinescopePlayerFactory = null;
  
          let kinescopePlayer = null;
  
          let initialVideoUri = '${UriBuilder.buildVideoUri(videoId: videoId)}';
  
          function onKinescopeIframeAPIReady(playerFactory) {
              kinescopePlayerFactory = playerFactory;
  
              loadVideo(initialVideoUri);
          }
  
          function loadVideo(videoUri) {
              if (kinescopePlayer != null) {
                  kinescopePlayer.destroy();
                  kinescopePlayer = null;
              }
  
              if (kinescopePlayerFactory != null) {
                  var devElement = document.createElement("div");
                  devElement.id = "player";
                  document.body.append(devElement);
  
                  kinescopePlayerFactory
                      .create('player', {
                          url: videoUri,
                          size: { width: '100%', height: '100%' },
                          settings: {
                            externalId: '${externalId}'
                          },
                          behaviour: ${UriBuilder.parametersToBehavior(widget.controller.parameters)},
                          ui: ${UriBuilder.parametersToUI(widget.controller.parameters)}
                      })
                      .then(function (player) {
                          kinescopePlayer = player;
                          player.once(player.Events.Ready, function (event) {
                          var time = ${UriBuilder.parameterSeekTo(widget.controller.parameters)};
                          if(time > 0 || time === 0) {
                             event.target.seekTo(time);
                          }
                          });
                          player.on(player.Events.Ready, function (event) { window.flutter_inappwebview.callHandler('events', 'ready'); });
                          player.on(player.Events.Playing, function (event) { window.flutter_inappwebview.callHandler('events', 'playing'); });
                          player.on(player.Events.Waiting, function (event) { window.flutter_inappwebview.callHandler('events', 'waiting'); });
                          player.on(player.Events.Pause, function (event) { window.flutter_inappwebview.callHandler('events', 'pause'); });
                          player.on(player.Events.Ended, function (event) { window.flutter_inappwebview.callHandler('events', 'ended'); });
                          player.on(player.Events.PlaybackRateChange, function (data) { window.flutter_inappwebview.callHandler('playbackRateEvent', data.data.playbackRate);});
                          player.on(player.Events.PipChange, function (data) { window.flutter_inappwebview.callHandler('pipChangeEvent', data.data.isPip);});
                          player.on(player.Events.FullscreenChange, async function (data) { 
                            if (${widget.useCustomFullscreen}) {
                              kinescopePlayer.setFullscreen(false);
                              if (data.data.isFullscreen) {
                                window.flutter_inappwebview.callHandler('onChangeFullscreen', data.data.isFullscreen);
                              }
                            } else {
                              window.flutter_inappwebview.callHandler('onChangeFullscreen', data.data.isFullscreen);
                            }
                          });
                      });
              }
          }
  
          function play() {
              if (kinescopePlayer != null)
                kinescopePlayer.play();
          }
                    
          function isPaused() {
              if (kinescopePlayer != null)
              kinescopePlayer.isPaused().then((value) => {
                  window.flutter_inappwebview.callHandler('isPaused', value);
                });
          }
  
          function pause() {
              if (kinescopePlayer != null)
                kinescopePlayer.pause();
          }
  
          function stop() {
              if (kinescopePlayer != null)
                kinescopePlayer.stop();
          }
  
          function getCurrentTime() {
              if (kinescopePlayer != null)
                return kinescopePlayer.getCurrentTime();
          }
  
          function seekTo(seconds) {
              if (kinescopePlayer != null)
                kinescopePlayer.seekTo(seconds);
          }
  
          function getCurrentTime() {
              if (kinescopePlayer != null)
                kinescopePlayer.getCurrentTime().then((value) => {
                  window.flutter_inappwebview.callHandler('getCurrentTimeResult', value);
                });
          }
  
          function getDuration() {
              if (kinescopePlayer != null)
                kinescopePlayer.getDuration().then((value) => {
                  window.flutter_inappwebview.callHandler('getDurationResult', value);
                });
          }
  
          function setVolume(value) {
              if (kinescopePlayer != null)
                kinescopePlayer.setVolume(value);
          }       
  
          function mute() {
              if (kinescopePlayer != null)
                kinescopePlayer.mute();
          }
          
          function getPlaybackRate() {
              if (kinescopePlayer != null)
                kinescopePlayer.getPlaybackRate().then((value) => {
                  window.flutter_inappwebview.callHandler('getPlaybackRateResult', value);
                });
          }
          function setPlaybackRate(value) {
              if (kinescopePlayer != null)
                kinescopePlayer.setPlaybackRate(value);
          }
  
          function unmute() {
              if (kinescopePlayer != null)
                kinescopePlayer.unmute();
          }
      </script>
  </head>
  
  <body>
      <script>
          var tag = document.createElement('script');
  
          tag.src = 'https://player.kinescope.io/latest/iframe.player.js';
          var firstScriptTag = document.getElementsByTagName('script')[0];
          firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
      </script>
  </body>
  
  </html>
''';
}
