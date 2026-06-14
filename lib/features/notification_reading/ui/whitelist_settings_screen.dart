import 'package:flutter/material.dart';

import '../service/notification_service.dart';

class WhitelistSettingsScreen extends StatefulWidget {
  const WhitelistSettingsScreen({super.key, required this.notificationService});

  final NotificationService notificationService;

  @override
  State<WhitelistSettingsScreen> createState() => _WhitelistSettingsScreenState();
}

class _WhitelistSettingsScreenState extends State<WhitelistSettingsScreen> {
  List<String> _people = <String>[];
  List<String> _groups = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final people = await widget.notificationService.getWhatsappPeopleWhitelist();
    final groups = await widget.notificationService.getWhatsappGroupsWhitelist();

    if (!mounted) return;
    setState(() {
      _people = people;
      _groups = groups;
      _loading = false;
    });
  }

  Future<void> _addGroup() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add WhatsApp group'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Group name (exact)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;
    await widget.notificationService.addWhatsappGroup(result);
    await _load();
  }

  Future<void> _addPerson() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        final personController = TextEditingController();
        final groupController = TextEditingController();
        bool alsoAddGroup = true;

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add WhatsApp person'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: personController,
                  decoration: const InputDecoration(hintText: "Person's name (exact)"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: groupController,
                  decoration: const InputDecoration(hintText: 'Optional group name'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: alsoAddGroup,
                      onChanged: (v) => setState(() => alsoAddGroup = v ?? true),
                    ),
                    const Expanded(child: Text('Also add the group to groups whitelist')),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, {
                  'person': personController.text.trim(),
                  'group': groupController.text.trim(),
                  'alsoAddGroup': alsoAddGroup,
                }),
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );

    if (result == null) return;
    final person = (result['person'] as String?) ?? '';
    final group = (result['group'] as String?) ?? '';
    final alsoAddGroup = result['alsoAddGroup'] as bool? ?? true;

    if (person.isEmpty) return;

    final entry = group.isEmpty ? person : '$group::$person';
    await widget.notificationService.addWhatsappPerson(entry);

    if (group.isNotEmpty && alsoAddGroup) {
      await widget.notificationService.addWhatsappGroup(group);
    }

    await _load();
  }

  Future<void> _removePerson(String entry) async {
    await widget.notificationService.removeWhatsappPerson(entry);
    await _load();
  }

  Future<void> _removeGroup(String group) async {
    await widget.notificationService.removeWhatsappGroup(group);
    await _load();
  }

  String _displayPerson(String entry) {
    if (entry.contains('::')) {
      final parts = entry.split('::');
      if (parts.length >= 2) {
        return '${parts[1]} (group: ${parts[0]})';
      }
    }
    return entry;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp whitelist'),
        actions: [
          IconButton(
            tooltip: 'Format help',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Whitelist format help'),
                  content: const Text(
                    'You can whitelist either a group or a person.\n\n'
                    '• To whitelist a whole group, add the group name under "Add group".\n'
                    '• To whitelist a person across all groups, add their exact name under "Add person".\n'
                    '• To whitelist a person only inside a specific group, use the person dialog and fill the group name — this creates an entry in the form "group::person" which matches messages from that person only when posted in that group.\n\n'
                    'Examples:\n'
                    'StudyGroup            (matches any messages in group StudyGroup)\n'
                    'Alice                 (matches private messages from Alice)\n'
                    'StudyGroup::Bob       (matches messages in StudyGroup from Bob)',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: ListView(
                children: [
                  const Text('Whitelisted groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_groups.isEmpty) const Text('No groups whitelisted'),
                  ..._groups.map((g) => Card(
                        child: ListTile(
                          title: Text(g),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => _removeGroup(g),
                          ),
                        ),
                      )),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _addGroup,
                    icon: const Icon(Icons.add),
                    label: const Text('Add group'),
                  ),
                  const SizedBox(height: 20),
                  const Text('Whitelisted people', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_people.isEmpty) const Text('No people whitelisted'),
                  ..._people.map((p) => Card(
                        child: ListTile(
                          title: Text(_displayPerson(p)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => _removePerson(p),
                          ),
                        ),
                      )),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _addPerson,
                    icon: const Icon(Icons.add),
                    label: const Text('Add person'),
                  ),
                ],
              ),
            ),
    );
  }
}
