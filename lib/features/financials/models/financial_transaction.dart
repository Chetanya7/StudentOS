class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.amount,
    required this.direction,
    required this.currency,
    required this.sourceApp,
    required this.message,
    required this.postTime,
    required this.reviewStatus,
    required this.category,
    required this.description,
    this.sender,
  });

  final String id;
  final double amount;
  final String direction;
  final String currency;
  final String sourceApp;
  final String message;
  final DateTime postTime;
  final String reviewStatus;
  final String category;
  final String description;
  final String? sender;

  bool get isDebit => direction == 'debit';
  bool get isCredit => direction == 'credit';
  bool get isAccepted => reviewStatus == 'accepted';
  bool get isRejected => reviewStatus == 'rejected';
  bool get isPending => !isAccepted && !isRejected;

  factory FinancialTransaction.fromJson(Map<String, dynamic> json) {
    return FinancialTransaction(
      id: json['id']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      direction: json['direction']?.toString() ?? 'unknown',
      currency: json['currency']?.toString() ?? 'INR',
      sourceApp: json['sourceApp']?.toString() ?? 'Unknown app',
      sender: json['sender']?.toString(),
      message: json['message']?.toString() ?? '',
      postTime: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['postTime']?.toString() ?? '') ?? 0,
      ),
      reviewStatus: json['reviewStatus']?.toString() ?? 'pending',
      category: json['category']?.toString() ?? 'Miscellaneous',
      description: json['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'direction': direction,
      'currency': currency,
      'sourceApp': sourceApp,
      'message': message,
      'postTime': postTime.millisecondsSinceEpoch,
      'reviewStatus': reviewStatus,
      'category': category,
      'description': description,
      if (sender != null) 'sender': sender,
    };
  }
}
