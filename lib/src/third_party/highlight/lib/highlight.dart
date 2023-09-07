import 'package:flutterware/src/third_party/highlight/lib/languages/all.dart';
import 'package:flutterware/src/third_party/highlight/lib/src/highlight.dart';

export 'package:flutterware/src/third_party/highlight/lib/src/highlight.dart';
export 'package:flutterware/src/third_party/highlight/lib/src/node.dart';
export 'package:flutterware/src/third_party/highlight/lib/src/mode.dart';
export 'package:flutterware/src/third_party/highlight/lib/src/result.dart';

final highlight = Highlight()..registerLanguages(allLanguages);
