import 'package:flutterware/motion.dart';

const checkoutStage = MotionStage(
  width: 360,
  height: 560,
  elements: [
    StageElement(target: 'first', x: 24, y: 80, width: 312, height: 48),
    StageElement(
      target: 'total',
      kind: StageKind.text,
      label: 'Total  £248.00',
      x: 24,
      y: 144,
      width: 220,
      height: 28,
    ),
    StageElement(target: 'card', x: 24, y: 188, width: 280, height: 90),
    StageElement(target: 'cta', x: 24, y: 294, width: 280, height: 46),
  ],
);
