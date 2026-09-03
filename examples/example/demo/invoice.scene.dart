//@flutterware:scene=0.6
// Target three of three: an invoice template, exported as a PDF.
//
// The line items are a list parameter: the file carries four of them as the
// mockup, a caller passes as many as the data has, and either way there is
// ONE authored row — `lineRow`, drawn once per item, its cells reading the
// item's fields. The table above it is what makes the columns agree: the
// tracks belong to the table, so every row is measured against the same
// ones whatever it happens to hold.

class Invoice({
  final String number = 'INV-2043',
  final String issued = '3 September 2026',
  final String billTo = 'Northwind Coffee Ltd',
  final String total = '£1,248.00',
  final List<Map<String, Object>> lines = const [
    {'item': 'Espresso beans, 1kg', 'qty': 12, 'amount': '£384.00'},
    {'item': 'Oat milk, 12 × 1L', 'qty': 8, 'amount': '£216.00'},
    {'item': 'Takeaway cups, 500', 'qty': 4, 'amount': '£148.00'},
    {'item': 'Filter papers, box', 'qty': 25, 'amount': '£500.00'},
  ],
}) {
  late final brand = Text(
    'ACME SUPPLY',
    fontSize: 18,
    weight: FontWeight.w700,
    color: Color(0xFF1B1210),
  );
  late final invoiceNo = Text(number, fontSize: 12, color: Color(0xFF6B5A52));
  late final issuedOn = Text(issued, fontSize: 12, color: Color(0xFF6B5A52));
  late final customer = Text(
    billTo,
    fontSize: 14,
    weight: FontWeight.w600,
    color: Color(0xFF1B1210),
  );
  late final header = Frame(
    x: 48,
    y: 48,
    width: 499,
    layout: NodeLayout.column,
    gap: 4,
    crossAlign: CrossAxisAlignment.start,
    children: [brand, invoiceNo, issuedOn, customer],
  );

  late final headItem = Text(
    'Item',
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
  );
  late final headQty = Text(
    'Qty',
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
    align: TextAlign.right,
  );
  late final headAmount = Text(
    'Amount',
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
    align: TextAlign.right,
  );
  late final headRow = Frame(
    fill: Color(0xFFF3E9E1),
    children: [headItem, headQty, headAmount],
  );

  late final lineItem = Text(lines.item, fontSize: 12);
  late final lineQty = Text(lines.qty, fontSize: 12, align: TextAlign.right);
  late final lineAmount = Text(
    lines.amount,
    fontSize: 12,
    align: TextAlign.right,
  );
  late final lineRow = Frame(
    borderColor: Color(0xFFEDE4DC),
    repeat: lines,
    children: [lineItem, lineQty, lineAmount],
  );

  late final table = Frame(
    x: 48,
    y: 200,
    width: 499,
    layout: NodeLayout.table,
    columns: [double.infinity, 48, 96],
    cellPadding: 8,
    children: [headRow, lineRow],
  );

  late final totalLabel = Text(
    'Total due',
    fontSize: 12,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
  );
  late final totalValue = Text(
    total,
    fontSize: 20,
    weight: FontWeight.w700,
    color: Color(0xFF1B1210),
  );
  late final totals = Frame(
    x: 48,
    y: 420,
    width: 499,
    layout: NodeLayout.column,
    gap: 4,
    crossAlign: CrossAxisAlignment.start,
    children: [totalLabel, totalValue],
  );

  late final root = Frame(
    width: 595,
    height: 842,
    fill: Color(0xFFFFFFFF),
    children: [header, table, totals],
  );
}
