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
