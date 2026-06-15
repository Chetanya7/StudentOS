import 'package:flutter/material.dart';

import '../models/sleep_models.dart';
import '../service/sleep_repository.dart';

class SleepSettingsScreen extends StatefulWidget {
  const SleepSettingsScreen({super.key, required this.repository});

  final SleepRepository repository;

  @override
  State<SleepSettingsScreen> createState() => _SleepSettingsScreenState();
}

class _SleepSettingsScreenState extends State<SleepSettingsScreen> {
  late Future<SleepSettings> _settingsFuture;
  late TextEditingController _goalController;
  TimeOfDay? _preferredBedtime;
  TimeOfDay? _preferredWakeTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _goalController = TextEditingController();
    _settingsFuture = _loadSettings();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<SleepSettings> _loadSettings() async {
    final settings = await widget.repository.getSettings();
    _goalController.text = (settings.sleepGoalMinutes / 60).toStringAsFixed(
      settings.sleepGoalMinutes % 60 == 0 ? 0 : 1,
    );
    _preferredBedtime = settings.preferredBedtime == null
        ? null
        : _timeOfDay(settings.preferredBedtime!);
    _preferredWakeTime = settings.preferredWakeTime == null
        ? null
        : _timeOfDay(settings.preferredWakeTime!);
    return settings;
  }

  Future<void> _pickPreferredBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _preferredBedtime ?? const TimeOfDay(hour: 23, minute: 0),
    );
    if (picked != null) setState(() => _preferredBedtime = picked);
  }

  Future<void> _pickPreferredWakeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _preferredWakeTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked != null) setState(() => _preferredWakeTime = picked);
  }

  Future<void> _save() async {
    final goalHours = double.tryParse(_goalController.text.trim()) ?? 8;
    final goalMinutes = (goalHours * 60).round().clamp(60, 16 * 60);

    setState(() => _isSaving = true);
    try {
      await widget.repository.saveSettings(
        SleepSettings(
          sleepGoalMinutes: goalMinutes,
          preferredBedtime: _preferredBedtime == null
              ? null
              : _minutesOfDay(_preferredBedtime!),
          preferredWakeTime: _preferredWakeTime == null
              ? null
              : _minutesOfDay(_preferredWakeTime!),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sleep settings saved.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save settings: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep Settings')),
      body: FutureBuilder<SleepSettings>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load settings: ${snapshot.error}'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sleep Goal Setup',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _goalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Daily sleep goal',
                          suffixText: 'hours',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bedtime_outlined),
                        title: const Text('Preferred bedtime'),
                        subtitle: Text(
                          _preferredBedtime?.format(context) ?? 'Optional',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (_preferredBedtime != null)
                              IconButton(
                                tooltip: 'Clear bedtime',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => _preferredBedtime = null);
                                },
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: _pickPreferredBedtime,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.wb_sunny_outlined),
                        title: const Text('Preferred wake-up time'),
                        subtitle: Text(
                          _preferredWakeTime?.format(context) ?? 'Optional',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (_preferredWakeTime != null)
                              IconButton(
                                tooltip: 'Clear wake-up time',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => _preferredWakeTime = null);
                                },
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: _pickPreferredWakeTime,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save sleep settings'),
              ),
            ],
          );
        },
      ),
    );
  }
}

TimeOfDay _timeOfDay(int minutes) {
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

int _minutesOfDay(TimeOfDay value) {
  return value.hour * 60 + value.minute;
}
