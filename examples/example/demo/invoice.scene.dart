//@flutterware:scene=0.8
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.
//
// This is ordinary Dart: it compiles, it analyzes, and an app mounts it.
import 'package:flutterware/scene_authoring.dart';

class Invoice({
  final String number = 'INV-2043',
  final String issued = '3 September 2026',
  final String billTo = 'Northwind Coffee Ltd',
  final String total = '£1,248.00',
  final List<({String item, String qty, String amount})> lines = const [
    (item: 'Espresso beans, 1kg', qty: '12', amount: '£384.00'),
    (item: 'Oat milk, 12 × 1L', qty: '8', amount: '£216.00'),
    (item: 'Takeaway cups, 500', qty: '4', amount: '£148.00'),
    (item: 'Filter papers, box', qty: '25', amount: '£500.00'),
  ],
}) extends SceneDefinition {
  late final brand = TextNode(
    'ACME SUPPLY',
    fontSize: 18,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFF1B1210),
  );
  late final invoiceNo = TextNode(
    number,
    fontSize: 12,
    color: SceneColor(0xFF6B5A52),
  );
  late final issuedOn = TextNode(
    issued,
    fontSize: 12,
    color: SceneColor(0xFF6B5A52),
  );
  late final customer = TextNode(
    billTo,
    fontSize: 14,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFF1B1210),
  );
  late final header = FrameNode(
    x: 48,
    y: 48,
    width: 499,
    layout: NodeLayout.column,
    gap: 4,
    crossAlign: SceneCrossAxisAlignment.start,
    children: [brand, invoiceNo, issuedOn, customer],
  );
  late final headItem = TextNode(
    'Item',
    fontSize: 11,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFF6B5A52),
  );
  late final headQty = TextNode(
    'Qty',
    fontSize: 11,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFF6B5A52),
    align: SceneTextAlign.right,
  );
  late final headAmount = TextNode(
    'Amount',
    fontSize: 11,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFF6B5A52),
    align: SceneTextAlign.right,
  );
  late final headRow = FrameNode(
    fill: SceneColor(0xFFF3E9E1),
    children: [headItem, headQty, headAmount],
  );
  late final lineRow = FrameNode.repeating(
    over: lines,
    row: (line) => [
      TextNode(line.item, fontSize: 12),
      TextNode(line.qty, fontSize: 12, align: SceneTextAlign.right),
      TextNode(line.amount, fontSize: 12, align: SceneTextAlign.right),
    ],
    borderColor: SceneColor(0xFFEDE4DC),
  );
  late final table = FrameNode(
    x: 48,
    y: 200,
    width: 499,
    layout: NodeLayout.table,
    columns: [double.infinity, 48, 96],
    cellPadding: 8,
    children: [headRow, lineRow],
  );
  late final totalLabel = TextNode(
    'Total due',
    fontSize: 12,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFF6B5A52),
  );
  late final totalValue = TextNode(
    total,
    fontSize: 20,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFF1B1210),
  );
  late final totals = FrameNode(
    x: 48,
    y: 420,
    width: 499,
    layout: NodeLayout.column,
    gap: 4,
    crossAlign: SceneCrossAxisAlignment.start,
    children: [totalLabel, totalValue],
  );
  @override
  late final root = FrameNode(
    width: 595,
    height: 842,
    fill: SceneColor(0xFFFFFFFF),
    children: [header, table, totals],
  );
}
