import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_models.dart';
import '../service/sleep_repository.dart';

class SleepHistoryScreen extends StatefulWidget {
  const SleepHistoryScreen({super.key, required this.repository});

  final SleepRepository repository;

  @override
  State<SleepHistoryScreen> createState() => _SleepHistoryScreenState();
}

class _SleepHistoryScreenState extends State<SleepHistoryScreen> {
  late Future<List<SleepRecord>> _recordsFuture;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _recordsFuture = widget.repository.getRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep History')),
      body: FutureBuilder<List<SleepRecord>>(
        future: _recordsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load history: ${snapshot.error}'),
            );
          }

          final records = _filterRecords(snapshot.data ?? const []);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('Last 7 days')),
                  ButtonSegment(value: 30, label: Text('Last 30 days')),
                ],
                selected: {_days},
                onSelectionChanged: (values) {
                  setState(() => _days = values.first);
                },
              ),
              const SizedBox(height: 14),
              if (records.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No sleep records in this range yet.'),
                    ),
                  ),
                )
              else
                ...records.map((record) => _SleepHistoryTile(record: record)),
            ],
          );
        },
      ),
    );
  }

  List<SleepRecord> _filterRecords(List<SleepRecord> records) {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: _days - 1));
    return records.where((record) {
      final date = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      return !date.isBefore(start);
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }
}

class _SleepHistoryTile extends StatelessWidget {
  const _SleepHistoryTile({required this.record});

  final SleepRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          foregroundColor: Colors.blue.shade700,
          child: const Icon(Icons.bedtime_outlined),
        ),
        title: Text(DateFormat('EEE, dd MMM').format(record.date)),
        subtitle: Text(
          '${formatSleepClock(record.sleepTime)} - ${formatSleepClock(record.wakeTime)}',
        ),
        trailing: Text(
          formatSleepDuration(record.durationMinutes),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
