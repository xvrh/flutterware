/// The TUI render tree (stage 3): a cell-based transcription of Flutter's
/// render layer. One library composed of [part] files so the tightly-coupled
/// classes can share library-private layout state.
library;

import '../cell.dart';
import '../geometry.dart';
import '../painter.dart';
import '../text_wrap.dart';

part 'box_constraints.dart';
part 'render_object.dart';
part 'render_box.dart';
part 'render_text.dart';
part 'render_padding.dart';
part 'render_constrained_box.dart';
part 'render_decorated_box.dart';
part 'render_flex.dart';
