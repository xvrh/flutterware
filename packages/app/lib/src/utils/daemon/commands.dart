import 'package:json_annotation/json_annotation.dart';

part 'commands.g.dart';

abstract class Command<TResult> {
  String get methodName;
  TResult decodeResult(covariant Object? result);
  Map<String, dynamic> toJson();
}

@JsonSerializable(createFactory: false)
class AppRestartCommand implements Command<AppRestartResult> {
  final String appId;
  final bool? fullRestart;
  final String? reason;
  final bool? pause;
  final bool? debounce;

  AppRestartCommand({
    required this.appId,
    this.fullRestart,
    this.reason,
    this.pause,
    this.debounce,
  });

  @override
  Map<String, dynamic> toJson() => _$AppRestartCommandToJson(this);

  @override
  String get methodName => 'app.restart';

  @override
  AppRestartResult decodeResult(Map<String, dynamic> result) =>
      AppRestartResult.fromJson(result);
}

@JsonSerializable(createToJson: false)
class AppRestartResult {
  final int code;
  final String message;

  AppRestartResult(this.code, this.message);

  factory AppRestartResult.fromJson(Map<String, dynamic> json) =>
      _$AppRestartResultFromJson(json);
}

@JsonSerializable(createFactory: false)
class AppStopCommand implements Command<bool> {
  final String appId;

  AppStopCommand({required this.appId});

  @override
  Map<String, dynamic> toJson() => _$AppStopCommandToJson(this);

  @override
  String get methodName => 'app.stop';

  @override
  bool decodeResult(bool result) => result;
}
