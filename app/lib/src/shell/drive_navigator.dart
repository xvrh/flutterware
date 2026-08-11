import 'package:flutter/widgets.dart';
import 'package:flutterware/drive.dart' show TargetError, TargetFailure;
import 'package:flutterware/plugins.dart' show Address;
import 'package:flutterware/run_guest.dart' show GuestDrive;

import 'shell_controller.dart';

/// Registers [shell] as this app's `navigate` handler, so a drive agent jumps
/// straight to an address instead of tapping through the rail — the trip an
/// agent makes most often through this GUI, in one call.
///
/// The route grammar is not invented here: it is [Address], the same `fw://`
/// string the address bar accepts, the search palette copies, and every
/// artifact carries. Whatever [ShellController.go] does with an address —
/// opening a closed worktree, canonicalising a branch name, letting a panel
/// complain about a segment it does not know — navigate does, because it *is*
/// a `go`. The two refusals below are the two ways a route can fail before
/// reaching `go`: not the grammar, or not a worktree git knows.
void registerDriveNavigator(ShellController shell) {
  GuestDrive.navigator = (route) {
    var address = Address.tryParse(route);
    if (address == null) {
      throw TargetError(
        TargetFailure.notFound,
        '`$route` is not a flutterware address — this app navigates by the '
        '`fw://` grammar: fw:///worktrees/<worktree>/<plugin>/<segments…>. '
        'The current screen is at `${shell.address}`.',
      );
    }
    address = _canonicalPlugin(shell, address);
    if (shell.go(address) == GoResult.worktreeUnknown) {
      throw TargetError(
        TargetFailure.notFound,
        '`$route` names no worktree git knows here — it reports: '
        '${shell.worktrees.map((w) => w.name).join(', ')}. '
        'The current screen is at `${shell.address}`.',
      );
    }
  };
}

/// Keeps [registerDriveNavigator] registered across hot reloads.
///
/// A widget mounted by `ShellApp` rather than a call from `main`: `main` runs
/// once per process, so a handler registered there only ever changes by hot
/// *restart*. Re-registering in [State.reassemble] makes the handler — and
/// any edit to it — arrive with every hot reload, the cadence everything else
/// in the drive loop already moves at.
class DriveNavigatorScope extends StatefulWidget {
  const DriveNavigatorScope({super.key, required this.shell, this.child});

  final ShellController shell;
  final Widget? child;

  @override
  State<DriveNavigatorScope> createState() => _DriveNavigatorScopeState();
}

class _DriveNavigatorScopeState extends State<DriveNavigatorScope> {
  @override
  void initState() {
    super.initState();
    registerDriveNavigator(widget.shell);
  }

  @override
  void reassemble() {
    super.reassemble();
    registerDriveNavigator(widget.shell);
  }

  @override
  void didUpdateWidget(DriveNavigatorScope old) {
    super.didUpdateWidget(old);
    if (old.shell != widget.shell) registerDriveNavigator(widget.shell);
  }

  @override
  void dispose() {
    GuestDrive.navigator = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox();
}

/// The plugin segment, resolved against what the worktree's session declares.
///
/// Without this, `previews` written where `flutterware.previews` is meant is
/// the worst outcome a navigate can have: [ShellController.go] accepts any
/// plugin segment, and the shell's fallback for an id the config does not
/// declare — home, quietly (see [ShellController.selectedPluginId]) — catches
/// a wrong id just as silently as the reloaded-config case it was written
/// for. The address bar says what you typed, the body shows Overview, and an
/// agent reads the ok and moves on. So: a short name that matches exactly one
/// declared `….<name>` is canonicalised and goes through; anything else that
/// resolves to no plugin refuses with the declared list, which is the reply
/// that teaches the grammar.
///
/// A worktree whose session has not loaded passes through untouched — its
/// plugin ids are not knowable yet, and refusing what may be about to become
/// valid would break `go`'s own promise that opening is the navigation.
Address _canonicalPlugin(ShellController shell, Address address) {
  var plugin = address.plugin;
  if (plugin == null || Address.shellOwned.contains(plugin)) return address;
  var name = address.worktree;
  var worktree = name == null ? null : shell.worktreeNamed(name);
  var session = worktree == null ? null : shell.sessionFor(worktree);
  if (session == null) return address;
  if (session.pluginById(plugin) != null) return address;
  var matches = [
    for (var candidate in session.plugins)
      if (candidate.id.endsWith('.$plugin')) candidate.id,
  ];
  if (matches.length == 1) return address.copyWith(plugin: matches.single);
  throw TargetError(
    TargetFailure.notFound,
    '`$plugin` is not a plugin this worktree declares'
    '${matches.isEmpty ? '' : ', and ${matches.join(', ')} all end in it'} — '
    'it has: ${session.plugins.map((p) => p.id).join(', ')}. '
    'The current screen is at `${shell.address}`.',
  );
}
