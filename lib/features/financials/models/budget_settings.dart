class BudgetSettings {
  const BudgetSettings({
    required this.budgetAmount,
    required this.alertAtAmount,
    required this.balanceBaseAmount,
  });

  final double budgetAmount;
  final double alertAtAmount;
  final double balanceBaseAmount;

  bool get isSet => budgetAmount > 0;

  Map<String, dynamic> toJson() {
    return {
      'budgetAmount': budgetAmount,
      'alertAtAmount': alertAtAmount,
      'balanceBaseAmount': balanceBaseAmount,
    };
  }

  factory BudgetSettings.fromJson(Map<String, dynamic> json) {
    return BudgetSettings(
      budgetAmount:
          double.tryParse(json['budgetAmount']?.toString() ?? '') ?? 0,
      alertAtAmount:
          double.tryParse(json['alertAtAmount']?.toString() ?? '') ?? 0,
      balanceBaseAmount:
          double.tryParse(json['balanceBaseAmount']?.toString() ?? '') ?? 0,
    );
  }
}
