import 'dart:convert';

import 'package:flutter/services.dart';

import '../../financials/models/budget_settings.dart';
import '../../financials/models/financial_transaction.dart';
import '../../financials/models/private_lending_entry.dart';
import '../../wellbeing/models/hydration_models.dart';
import '../models/notification_llm_input.dart';

class NotificationService {
  static const MethodChannel _channel = MethodChannel(
    'studentos/notification_service',
  );

  /// Returns true if notification-listener access is granted.
  Future<bool> hasPermission() async {
    final bool granted = await _channel.invokeMethod('checkPermission');
    return granted;
  }

  /// Returns true if the service should prompt the user to enable access.
  Future<bool> shouldAsk() async {
    final bool ask = await _channel.invokeMethod('shouldAsk');
    return ask;
  }

  /// Opens the system settings page where the user can grant notification access.
  Future<void> openSettings() async {
    await _channel.invokeMethod('openSettings');
  }

  /// Record that the user denied the prompt and should not be asked again.
  Future<void> markDontAskAgain() async {
    await _channel.invokeMethod('markDontAskAgain');
  }

  Future<List<String>> getEnabledApps() async {
    final List<dynamic> values = await _channel.invokeMethod('getEnabledApps');
    return values.cast<String>();
  }

  Future<List<NotificationLlmInputPayload>> drainPendingNotifications() async {
    final String source = await _channel.invokeMethod(
      'drainPendingNotificationPayloads',
    );
    final List<dynamic> values = source.isEmpty
        ? <dynamic>[]
        : jsonDecode(source);
    return values
        .whereType<Map>()
        .map(
          (value) => NotificationLlmInputPayload.fromJson(
            value.cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<List<FinancialTransaction>> getFinancialTransactions() async {
    final String source = await _channel.invokeMethod(
      'getFinancialTransactions',
    );
    final List<dynamic> values = source.isEmpty
        ? <dynamic>[]
        : jsonDecode(source);
    return values
        .whereType<Map>()
        .map(
          (value) =>
              FinancialTransaction.fromJson(value.cast<String, dynamic>()),
        )
        .toList()
      ..sort((a, b) => b.postTime.compareTo(a.postTime));
  }

  Future<void> addFinancialTransaction(FinancialTransaction transaction) async {
    await _channel.invokeMethod('addFinancialTransaction', {
      'transaction': transaction.toJson(),
    });
  }

  Future<void> setFinancialTransactionReviewStatus({
    required String id,
    required String reviewStatus,
  }) async {
    await _channel.invokeMethod('setFinancialTransactionReviewStatus', {
      'id': id,
      'reviewStatus': reviewStatus,
    });
  }

  Future<void> setFinancialTransactionDetails({
    required String id,
    required String category,
    required String description,
  }) async {
    await _channel.invokeMethod('setFinancialTransactionDetails', {
      'id': id,
      'category': category,
      'description': description,
    });
  }

  Future<BudgetSettings> getBudgetSettings() async {
    final String source = await _channel.invokeMethod('getBudgetSettings');
    final decoded = source.isEmpty ? <String, dynamic>{} : jsonDecode(source);
    return BudgetSettings.fromJson(
      decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{},
    );
  }

  Future<void> setBudgetSettings(BudgetSettings budget) async {
    await _channel.invokeMethod('setBudgetSettings', {
      'budget': budget.toJson(),
    });
  }

  Future<List<PrivateLendingEntry>> getPrivateLendingEntries() async {
    final String source = await _channel.invokeMethod(
      'getPrivateLendingEntries',
    );
    final List<dynamic> values = source.isEmpty
        ? <dynamic>[]
        : jsonDecode(source);
    return values
        .whereType<Map>()
        .map(
          (value) =>
              PrivateLendingEntry.fromJson(value.cast<String, dynamic>()),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> addPrivateLendingEntry(PrivateLendingEntry entry) async {
    await _channel.invokeMethod('addPrivateLendingEntry', {
      'entry': entry.toJson(),
    });
  }

  Future<void> setEnabledApps(List<String> apps) async {
    await _channel.invokeMethod('setEnabledApps', {'apps': apps});
  }

  Future<void> addEnabledApp(String packageName) async {
    await _channel.invokeMethod('addEnabledApp', {'packageName': packageName});
  }

  Future<void> removeEnabledApp(String packageName) async {
    await _channel.invokeMethod('removeEnabledApp', {
      'packageName': packageName,
    });
  }

  Future<List<String>> getWhatsappPeopleWhitelist() async {
    final List<dynamic> values = await _channel.invokeMethod(
      'getWhatsappPeopleWhitelist',
    );
    return values.cast<String>();
  }

  Future<void> setWhatsappPeopleWhitelist(List<String> values) async {
    await _channel.invokeMethod('setWhatsappPeopleWhitelist', {
      'values': values,
    });
  }

  Future<void> addWhatsappPerson(String name) async {
    await _channel.invokeMethod('addWhatsappPerson', {'name': name});
  }

  Future<void> removeWhatsappPerson(String name) async {
    await _channel.invokeMethod('removeWhatsappPerson', {'name': name});
  }

  Future<List<String>> getWhatsappGroupsWhitelist() async {
    final List<dynamic> values = await _channel.invokeMethod(
      'getWhatsappGroupsWhitelist',
    );
    return values.cast<String>();
  }

  Future<void> setWhatsappGroupsWhitelist(List<String> values) async {
    await _channel.invokeMethod('setWhatsappGroupsWhitelist', {
      'values': values,
    });
  }

  Future<void> addWhatsappGroup(String name) async {
    await _channel.invokeMethod('addWhatsappGroup', {'name': name});
  }

  Future<void> removeWhatsappGroup(String name) async {
    await _channel.invokeMethod('removeWhatsappGroup', {'name': name});
  }

  Future<void> showAcademicAlert({
    required String title,
    required String message,
  }) async {
    await _channel.invokeMethod('showAcademicAlert', {
      'title': title,
      'message': message,
    });
  }

  Future<void> scheduleHydrationReminders(HydrationSettings settings) async {
    try {
      await _channel.invokeMethod('scheduleHydrationReminders', {
        'settings': settings.toJson(),
      });
    } on MissingPluginException {
      // Hydration scheduling is currently implemented by the Android host.
    }
  }

  Future<void> cancelHydrationReminders() async {
    try {
      await _channel.invokeMethod('cancelHydrationReminders');
    } on MissingPluginException {
      // Hydration scheduling is currently implemented by the Android host.
    }
  }
}
