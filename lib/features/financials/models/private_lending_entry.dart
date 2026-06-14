class PrivateLendingEntry {
  const PrivateLendingEntry({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.amount,
    required this.direction,
    required this.createdAt,
    required this.description,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final double amount;
  final String direction;
  final DateTime createdAt;
  final String description;

  bool get isLent => direction == 'lent';
  bool get isBorrowed => direction == 'borrowed';
  bool get isPerson => direction == 'person';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'amount': amount,
      'direction': direction,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'description': description,
    };
  }

  factory PrivateLendingEntry.fromJson(Map<String, dynamic> json) {
    return PrivateLendingEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      direction: json['direction']?.toString() ?? 'lent',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      ),
      description: json['description']?.toString() ?? '',
    );
  }
}
