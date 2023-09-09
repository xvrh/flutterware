import 'languages/all.dart';
import 'src/highlight.dart';

export 'src/highlight.dart';
export 'src/mode.dart';
export 'src/node.dart';
export 'src/result.dart';

final highlight = Highlight()..registerLanguages(allLanguages);
