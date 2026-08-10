/// The Motion vocabulary, with no Flutter in it.
///
/// `package:flutterware/motion.dart` is the runtime and needs widgets. This is
/// the same closed set of property names, kinds, identities and slider hints,
/// reachable from a plain Dart VM — for the half of the tooling that **reads
/// code rather than runs it**: the syntactic scanner, `fw`, MCP.
///
/// It exists because those entry points are compiled with `dart compile exe`,
/// where `package:flutter` cannot load at all. A scanner that wants to know
/// whether `title.opacity` names a property should not have to link a UI
/// toolkit to find out, and until this library existed it did — which the
/// entry-point purity test caught the moment the scanner shipped.
///
/// Everything here is also exported by `motion.dart`, so a Flutter app needs
/// only the one import.
library;

export 'src/motion/vocabulary.dart'
    show
        MotionProp,
        MotionValueKind,
        motionBoxProps,
        motionVocabulary,
        motionVocabularyByName;
