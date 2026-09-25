/// The final-amount rules in the supplied LKS/LKA Excel forms.
class DocumentAmounts {
  DocumentAmounts._();

  static bool usesExcelRules(String routeKey) =>
      routeKey == 'kr_la_sea' || routeKey == 'kr_la_air';

  // Excel M20: FIND("세금 계산서", A18), then 10%.
  static double vatRate(String routeKey, String remark) =>
      usesExcelRules(routeKey) && remark.contains('세금 계산서') ? .1 : 0;

  static bool requiresTaxInvoice(String remark) =>
      remark.replaceAll(RegExp(r'[\s\u00a0\u3000]+'), '').contains('세금계산서');

  static ({String number, String holder}) krwAccount(String remark) =>
      requiresTaxInvoice(remark)
          ? (number: '2070133424601', holder: '박성호(엘케이무역)')
          : (number: '571-22-0330221', holder: '박성호');

  // Excel N23: ROUNDUP(USD * THB exchange rate, -1).
  static double thb(num value) => (value.abs() / 10).ceil() * 10.0 * value.sign;

  static ({double regular, double special, double vat, double total}) totals({
    required double gross, required double exempt, required double regular,
    required double special, double vatRate = 0,
  }) {
    final eligible = (gross - exempt).clamp(0, double.infinity).toDouble();
    final regularAmount = regular.clamp(0, eligible).toDouble();
    final specialAmount = special.clamp(0, eligible - regularAmount).toDouble();
    final net = gross - regularAmount - specialAmount;
    final tax = net * vatRate;
    return (regular: regularAmount, special: specialAmount, vat: tax, total: net + tax);
  }
}
