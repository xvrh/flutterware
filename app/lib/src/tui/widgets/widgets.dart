/// The TUI widget layer (stage 4): a transcription of Flutter's framework
/// layer. One library composed of [part] files so the tightly-coupled
/// Widget/Element/State classes share library-private lifecycle state.
library;

import 'dart:async';

import '../cell.dart';
import '../geometry.dart';
import '../input.dart';
import '../painter.dart';
import '../render/render.dart';
import '../terminal.dart';

part 'key.dart';
part 'widget.dart';
part 'element.dart';
part 'build_owner.dart';
part 'inherited.dart';
part 'render_object_widget.dart';
part 'basic.dart';
part 'binding.dart';
