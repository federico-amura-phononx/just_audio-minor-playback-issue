// This is a minimal example demonstrating a play/pause button and a seek bar.
// More advanced examples demonstrating other features can be found in the same
// directory as this example in the GitHub repository.

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';
import 'package:rxdart/rxdart.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AudioPlayer? _player;

  Timer? _timer;
  final Duration _delay = const Duration(seconds: 5);
  Duration _timerValue = Duration.zero;

  final _list = <String>[
    "https://download.samplelib.com/mp3/sample-3s.mp3",
    "https://download.samplelib.com/mp3/sample-6s.mp3",
    "https://download.samplelib.com/mp3/sample-9s.mp3",
  ];
  int _currentIndex = -1;
  bool _waiting = false;

  final _streamSubcriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.black));
    _init();
  }

  Future<void> _init() async {
    // Inform the operating system of our app's audio attributes etc.
    // We pick a reasonable default for an app that plays speech.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  _startTimer() {
    setState(() {
      _timerValue = Duration.zero;
      _waiting = true;
    });

    const t = Duration(milliseconds: 100);
    _timer?.cancel();
    Duration elapsed = Duration.zero;
    _timer = Timer.periodic(t, (timer) {
      elapsed += t;
      setState(() {
        _timerValue = elapsed;
      });

      if (elapsed >= _delay) {
        setState(() {
          _waiting = false;
        });

        _timer?.cancel();
        _playNext();
      }
    });
  }

  _playNext() async {
    int index = _currentIndex + 1;
    if (index >= _list.length) {
      index = 0;
    }

    setState(() {
      _currentIndex = index;
    });

    for (var element in _streamSubcriptions) {
      element.cancel();
    }
    _streamSubcriptions.clear();

    await _player?.dispose();
    final player = AudioPlayer();
    setState(() {
      _player = player;
    });

    final subscription = player.playerStateStream.listen((event) {
      if (event.processingState == ProcessingState.completed && event.playing) {
        _startTimer();
      }
    });
    _streamSubcriptions.add(subscription);

    final current = _list[_currentIndex];
    try {
      await player.setAudioSource(AudioSource.uri(Uri.parse(current)));
      await player.play();
    } catch (e) {
      print("Error loading audio source: $e");
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    // Release decoders and buffers back to the operating system making them
    // available for other apps to use.
    for (var element in _streamSubcriptions) {
      element.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      _player?.stop();
    }
  }

  /// Collects the data useful for displaying in a seek bar, using a handy
  /// feature of rx_dart to combine the 3 streams of interest into one.
  Stream<PositionData> _positionDataStream(AudioPlayer player) => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      player.positionStream,
      player.bufferedPositionStream,
      player.durationStream,
      (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    final player = _player;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (player == null) ...[
                Center(
                  child: ElevatedButton(
                    onPressed: _playNext,
                    child: const Text("Start"),
                  ),
                ),
              ],
              if (player != null) ...[
                // Display play/pause button and volume/speed sliders.
                Text("Current index: $_currentIndex"),
                if (_waiting) Text("The next audio will play in: ${(_delay - _timerValue).toString()}"),
                ControlButtons(player),
                StreamBuilder<PositionData>(
                  stream: _positionDataStream(player),
                  builder: (context, snapshot) {
                    final positionData = snapshot.data;
                    return SeekBar(
                      duration: positionData?.duration ?? Duration.zero,
                      position: positionData?.position ?? Duration.zero,
                      bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
                      onChangeEnd: player.seek,
                    );
                  },
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Opens volume slider dialog
        IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              value: player.volume,
              stream: player.volumeStream,
              onChanged: player.setVolume,
            );
          },
        ),

        /// This StreamBuilder rebuilds whenever the player state changes, which
        /// includes the playing/paused state and also the
        /// loading/buffering/ready state. Depending on the state we show the
        /// appropriate button or loading indicator.
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: player.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => player.seek(Duration.zero),
              );
            }
          },
        ),
        // Opens speed slider dialog
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x", style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                value: player.speed,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}
