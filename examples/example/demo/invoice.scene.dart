//@flutterware:scene=0.5
// Target three of three: an invoice template, exported as a PDF.
//
// The rows below are the mockup standing in for data. There are four of them
// because four is what fits and what could be typed, not because an invoice
// has four lines: the real one has as many as the data has, and every row is
// the same row with different values. That is the thing this target exists to
// show the model cannot say yet.

class Invoice({
  final String number = 'INV-2043',
  final String issued = '3 September 2026',
  final String billTo = 'Northwind Coffee Ltd',
  final String total = '£1,248.00',
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

  late final colItem = Text(
    'Item',
    width: double.infinity,
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
  );
  late final colQty = Text(
    'Qty',
    width: 48,
    align: TextAlign.right,
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
  );
  late final colPrice = Text(
    'Amount',
    width: 96,
    align: TextAlign.right,
    fontSize: 11,
    weight: FontWeight.w600,
    color: Color(0xFF6B5A52),
  );
  late final columns = Frame(
    width: 499,
    fill: Color(0xFFF3E9E1),
    layout: NodeLayout.row,
    gap: 24,
    padding: 8,
    children: [colItem, colQty, colPrice],
  );

  late final item1 = Text(
    'Espresso beans, 1kg',
    width: double.infinity,
    fontSize: 12,
  );
  late final qty1 = Text('12', width: 48, align: TextAlign.right, fontSize: 12);
  late final price1 = Text(
    '£384.00',
    width: 96,
    align: TextAlign.right,
    fontSize: 12,
  );
  late final row1 = Frame(
    width: 499,
    layout: NodeLayout.row,
    gap: 24,
    padding: 8,
    borderColor: Color(0xFFEDE4DC),
    children: [item1, qty1, price1],
  );

  late final item2 = Text(
    'Oat milk, 12 × 1L',
    width: double.infinity,
    fontSize: 12,
  );
  late final qty2 = Text('8', width: 48, align: TextAlign.right, fontSize: 12);
  late final price2 = Text(
    '£216.00',
    width: 96,
    align: TextAlign.right,
    fontSize: 12,
  );
  late final row2 = Frame(
    width: 499,
    layout: NodeLayout.row,
    gap: 24,
    padding: 8,
    borderColor: Color(0xFFEDE4DC),
    children: [item2, qty2, price2],
  );

  late final item3 = Text(
    'Takeaway cups, 500',
    width: double.infinity,
    fontSize: 12,
  );
  late final qty3 = Text('4', width: 48, align: TextAlign.right, fontSize: 12);
  late final price3 = Text(
    '£148.00',
    width: 96,
    align: TextAlign.right,
    fontSize: 12,
  );
  late final row3 = Frame(
    width: 499,
    layout: NodeLayout.row,
    gap: 24,
    padding: 8,
    borderColor: Color(0xFFEDE4DC),
    children: [item3, qty3, price3],
  );

  late final item4 = Text(
    'Filter papers, box',
    width: double.infinity,
    fontSize: 12,
  );
  late final qty4 = Text('25', width: 48, align: TextAlign.right, fontSize: 12);
  late final price4 = Text(
    '£500.00',
    width: 96,
    align: TextAlign.right,
    fontSize: 12,
  );
  late final row4 = Frame(
    width: 499,
    layout: NodeLayout.row,
    gap: 24,
    padding: 8,
    borderColor: Color(0xFFEDE4DC),
    children: [item4, qty4, price4],
  );

  late final table = Frame(
    x: 48,
    y: 200,
    width: 499,
    layout: NodeLayout.column,
    gap: 0,
    crossAlign: CrossAxisAlignment.start,
    children: [columns, row1, row2, row3, row4],
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
