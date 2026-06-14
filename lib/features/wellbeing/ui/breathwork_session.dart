import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

enum _BreathingPhase { inhale, holdAfterInhale, exhale, holdAfterExhale }

class BreathworkSession extends StatefulWidget {
  const BreathworkSession({super.key});

  @override
  State<BreathworkSession> createState() => _BreathworkSessionState();
}

class _BreathworkSessionState extends State<BreathworkSession>
    with SingleTickerProviderStateMixin {
  static const totalSeconds = 120;
  static const phaseDuration = 4;
  static const _phases = [
    _BreathingPhase.inhale,
    _BreathingPhase.holdAfterInhale,
    _BreathingPhase.exhale,
    _BreathingPhase.holdAfterExhale,
  ];

  late Timer _timer;
  int _remaining = totalSeconds;
  int _phaseRemaining = phaseDuration;
  int _phaseIndex = 0;
  late AnimationController _breathController;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: phaseDuration),
    )..repeat(reverse: true);
    _startTimer();
    _startMusic();
  }

  Future<void> _startMusic() async {
    try {
      await _player.setSource(AssetSource('audio/calm_ocean.mp3'));
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.resume();
    } catch (_) {
      // ignore audio failures
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _remaining = totalSeconds - t.tick;
        _phaseRemaining = _phaseRemaining - 1;
        if (_phaseRemaining <= 0) {
          _phaseIndex = (_phaseIndex + 1) % _phases.length;
          _phaseRemaining = phaseDuration;
        }
      });

      if (t.tick >= totalSeconds) {
        t.cancel();
        _onComplete();
      }
    });
  }

  Future<void> _onComplete() async {
    await _player.stop();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Nice work! You completed your 2-minute breathwork.'),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _breathController.dispose();
    _player.dispose();
    super.dispose();
  }

  String get _phaseLabel {
    switch (_phases[_phaseIndex]) {
      case _BreathingPhase.inhale:
        return 'Inhale';
      case _BreathingPhase.holdAfterInhale:
        return 'Hold';
      case _BreathingPhase.exhale:
        return 'Exhale';
      case _BreathingPhase.holdAfterExhale:
        return 'Hold';
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_remaining / 60).floor();
    final seconds = _remaining % 60;

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(title: const Text('2-minute breathwork')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1.2).animate(_breathController),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(140),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _phaseLabel,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.indigo.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: Colors.indigo.shade900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Breathe on a 4s cycle: inhale, hold, exhale, hold. Repeat until complete.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.indigo.shade900,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await _player.stop();
                    _timer.cancel();
                    if (!mounted) return;
                    navigator.popUntil((route) => route.isFirst);
                  },
                  child: const Text('Skip'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
