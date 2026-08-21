import 'dart:convert';
import 'dart:io';

/// Spawning git without inheriting an unrelated repository.
///
/// A git hook exports `GIT_DIR` to everything it runs, and `GIT_DIR` **beats
/// every other way of saying which repository** — the working directory, and
/// `-C` too, because `-C` only moves the process before the same environment
/// lookup happens. So flutterware started from a hook — or from any tool that
/// leaks these variables — would run all of its git against the hook's
/// repository, wherever it was pointed: measured, `GIT_DIR=<a> git -C <b> log`
/// answers from `<a>`. A consumer hit exactly this, and the command that
/// landed in the wrong repository was one that *writes*.
///
/// Setting `GIT_DIR` to the empty string is not the antidote: git treats it as
/// a repository named `''` and every command dies with *"fatal: not a git
/// repository"* (measured, git 2.49). The variable has to be **absent**, and
/// `Process.run`'s `environment:` map can only add — so these helpers rebuild
/// the environment (`includeParentEnvironment: false`) from a copy of the
/// parent's with the redirecting variables removed.

/// The variables through which a surrounding git invocation names *its*
/// repository: where the repository is, which work tree, which index, which
/// object store — plus the ones a server-side hook gets (`GIT_QUARANTINE_PATH`,
/// `GIT_NAMESPACE`). Everything else the parent set stays, on purpose:
/// `GIT_SSH_COMMAND`, `GIT_ASKPASS`, author identity and the `GIT_CONFIG_*`
/// family are the user's machine setup, and dropping them breaks fetch
/// authentication for no gain — none of them can point a command at the wrong
/// repository.
const _repositoryRedirects = {
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_COMMON_DIR',
  'GIT_OBJECT_DIRECTORY',
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_QUARANTINE_PATH',
  'GIT_PREFIX',
  'GIT_NAMESPACE',
  'GIT_GRAFT_FILE',
  'GIT_SHALLOW_FILE',
};

/// [base] (the parent environment when null) minus the variables that would
/// redirect a git command to another repository.
///
/// Matched case-insensitively: Windows environment lookup ignores case, so a
/// leaked `Git_Dir` redirects git there just the same.
Map<String, String> environmentForGit([Map<String, String>? base]) => {
  for (var MapEntry(:key, :value) in (base ?? Platform.environment).entries)
    if (!_repositoryRedirects.contains(key.toUpperCase())) key: value,
};

/// Runs git on the repository the arguments name — cwd or `-C` — immune to a
/// leaked `GIT_DIR`.
Future<ProcessResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
}) => runGitTool(
  'git',
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: stdoutEncoding,
  stderrEncoding: stderrEncoding,
);

/// [runGit] for a named executable — the default for the `RunProcess` seams,
/// whose callers spawn `gh` and `glab` as well as git. The forge CLIs work out
/// which repository they are in by running git themselves, so they inherit the
/// leak exactly the way a direct spawn does.
///
/// The extra named parameters do not break the seam shape: a function with
/// more optional parameters still satisfies the narrower type.
Future<ProcessResult> runGitTool(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environmentForGit(),
  includeParentEnvironment: false,
  stdoutEncoding: stdoutEncoding,
  stderrEncoding: stderrEncoding,
);
