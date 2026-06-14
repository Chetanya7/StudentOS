import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../wellbeing/service/wellbeing_service.dart';
import 'breathwork_session.dart';

class WellbeingPromptScreen extends StatefulWidget {
  final WellbeingService wellbeingService;

  const WellbeingPromptScreen({super.key, required this.wellbeingService});

  @override
  State<WellbeingPromptScreen> createState() => _WellbeingPromptScreenState();
}

class _WellbeingPromptScreenState extends State<WellbeingPromptScreen>
    with TickerProviderStateMixin {
  late final AnimationController _cloudController;
  late final AnimationController _messageController;
  Timer? _returnTimer;
  String? _selectedChoice;
  String? _selectedMessage;

  @override
  void initState() {
    super.initState();
    _cloudController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _messageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    widget.wellbeingService.markPromptShownNow();
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    _cloudController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onChoice(String choice) {
    if (_selectedChoice != null) return;

    if (choice == 'Stressed') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BreathworkSession()),
      );
      return;
    }

    String message;
    switch (choice) {
      case 'Sad':
        message = "It's okay to be sad sometimes. Hang out with friends today if possible — it helps.";
        break;
      case 'Fine':
        message = 'Glad to hear that.';
        break;
      case 'Amazing':
        message = "That's awesome — keep it up!";
        break;
      default:
        message = '';
    }

    setState(() {
      _selectedChoice = choice;
      _selectedMessage = message;
    });

    _messageController.forward(from: 0);
    _returnTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.maybePop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFBEE9FF),
      body: SafeArea(
        child: Stack(
          children: [
            // moving clouds
            AnimatedBuilder(
              animation: _cloudController,
              builder: (context, child) {
                final t = _cloudController.value;
                return Positioned(
                  left: MediaQuery.of(context).size.width * (t * 1.2 - 0.1),
                  top: 40,
                  child: Opacity(
                    opacity: 0.9,
                    child: Icon(Icons.cloud, size: 120, color: Colors.white70),
                  ),
                );
              },
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'How have you been feeling today?',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildChoice('Sad', '😔'),
                        _buildChoice('Stressed', '😰'),
                        _buildChoice('Fine', '🙂'),
                        _buildChoice('Amazing', '🤩'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            if (_selectedMessage != null) _buildMoodResponseOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildChoice(String label, String emoji) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _selectedChoice == null ? () => _onChoice(label) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildMoodResponseOverlay() {
    final choice = _selectedChoice ?? '';
    final message = _selectedMessage ?? '';
    final accent = switch (choice) {
      'Sad' => const Color(0xFF6C7DF7),
      'Fine' => const Color(0xFF25B89A),
      'Amazing' => const Color(0xFFFF9F1C),
      _ => Colors.indigo,
    };
    final icon = switch (choice) {
      'Sad' => Icons.favorite,
      'Fine' => Icons.wb_sunny_rounded,
      'Amazing' => Icons.auto_awesome,
      _ => Icons.spa,
    };

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _messageController,
        builder: (context, child) {
          final eased = Curves.easeOutBack.transform(_messageController.value);
          final fade = CurvedAnimation(
            parent: _messageController,
            curve: Curves.easeOut,
          ).value;

          return Opacity(
            opacity: fade,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.indigo.shade900.withOpacity(0.18),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Transform.translate(
                  offset: Offset(0, 28 * (1 - fade)),
                  child: Transform.scale(
                    scale: 0.84 + (0.16 * eased),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.96),
                            accent.withOpacity(0.18),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.28),
                            blurRadius: 32,
                            offset: const Offset(0, 18),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 86,
                                height: 86,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent.withOpacity(0.16),
                                ),
                              ),
                              Transform.rotate(
                                angle: -0.18 + (0.18 * fade),
                                child: Icon(icon, color: accent, size: 48),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Text(
                            choice,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.indigo.shade900,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.indigo.shade900,
                                      height: 1.45,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 5,
                              value: null,
                              backgroundColor: accent.withOpacity(0.12),
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
