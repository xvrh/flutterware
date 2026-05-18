/// Returns a copy of [args] with `--dart-define=<key>=<value>` inserted
/// immediately after the subcommand token (the first non-flag argument,
/// e.g. `run` in `flutter run`). If there is no non-flag token, the define
/// is appended at the end.
List<String> injectDartDefine(
  List<String> args, {
  required String key,
  required String value,
}) {
  final define = '--dart-define=$key=$value';
  final idx = args.indexWhere((a) => !a.startsWith('-'));
  if (idx == -1) return [...args, define];
  return [...args.sublist(0, idx + 1), define, ...args.sublist(idx + 1)];
}
