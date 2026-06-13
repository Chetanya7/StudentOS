import 'package:flutter/services.dart';

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
}
