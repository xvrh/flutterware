/// How strongly a guard objects to closing a worktree.
enum GuardLevel {
  /// Proceed is allowed; an acknowledgement line is shown.
  warn,

  /// Hard stop — teardown is disabled with the reason shown.
  block,
}

/// A plugin's objection to tearing a worktree down, raised *before* the
/// checklist renders.
///
/// Distinct from a teardown step: a step is something you may choose to run, a
/// guard is a reason not to start. Git motivates [GuardLevel.block] (do not
/// destroy uncommitted work); Claude motivates [GuardLevel.warn] (it is
/// mid-task, but you may know better).
class Guard {
  const Guard(this.level, this.reason);

  const Guard.warn(String reason) : this(GuardLevel.warn, reason);
  const Guard.block(String reason) : this(GuardLevel.block, reason);

  final GuardLevel level;
  final String reason;

  Map<String, Object?> toJson() => {'level': level.name, 'reason': reason};

  static Guard fromJson(Map<String, Object?> json) => Guard(
    GuardLevel.values.firstWhere(
      (l) => l.name == json['level'],
      orElse: () => GuardLevel.warn,
    ),
    json['reason']! as String,
  );
}
