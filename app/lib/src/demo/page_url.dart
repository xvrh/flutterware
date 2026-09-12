import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/plugins.dart';

import '../shell/shell_controller.dart';
import '../utils/url_fragment.dart' as url;

/// The page's URL is the shell's address, so any place in the demo is a link.
///
/// ```
/// …/flutterware/#/worktrees/~/flutterware.previews/./demo/shop.dart%23shopConfirmation
/// ```
///
/// The fragment is the address with its `fw://` taken off — the same string
/// the address bar at the bottom of the window shows, so a link copied from
/// either pastes into the other, into `fw` and into an agent. A fragment rather
/// than a path because Pages serves one `index.html` and nothing under it, and
/// because the root package's id is `.`: a browser resolves `/./` out of a
/// path, and never out of a fragment.
///
/// **A history entry needs a hand.** A press — a pointer or a key going down —
/// arms one push, and the next move to another place spends it; every other
/// write replaces the entry it is on. The other writes are the panels': a
/// scenario panel restoring its device, a catalog settling on the entry an
/// address named. Pushed, each one is a back button that returns to where the
/// panel was *before* it corrected itself — which it then corrects again, and
/// the forward entry is gone. Nobody pressed anything for those, so nobody
/// should have to press back through them.
///
/// Spent by the move rather than by the release, because a press does not
/// always move the address while it lasts. A demo clicked in the catalog is
/// not written until it has compiled and drawn — measured at about a second on
/// the deployed page — and it is still the click's place.
///
/// Axes alone never push, and never spend the press. A knob dragged across a
/// range is one place seen fifty ways, not fifty places.
class PageUrl {
  PageUrl(
    this.shell, {
    void Function(String fragment)? replace,
    void Function(String fragment)? push,
    Stream<String>? changes,
  }) : _replace = replace ?? url.writeUrlFragment,
       _push = push ?? url.pushUrlFragment,
       _changes = changes ?? url.urlFragmentChanges;

  final ShellController shell;
  final void Function(String) _replace;
  final void Function(String) _push;
  final Stream<String> _changes;

  /// The address a fragment names, or null when it names none — empty, or not
  /// an address at all. Raw or decoded: the escapes are the address's own.
  ///
  /// The leading `/` is required, because it is what an empty authority leaves:
  /// without it `#section-2` would parse as an address of a project by that
  /// name.
  static Address? addressOf(String fragment) => fragment.startsWith('/')
      ? Address.tryParse('${Address.scheme}://$fragment')
      : null;

  /// The fragment that names [address].
  static String fragmentOf(Address address) =>
      '$address'.substring('${Address.scheme}://'.length);

  StreamSubscription<String>? _subscription;
  Address? _written;
  var _flushing = false;
  var _armed = false;

  /// Starts keeping the two in step. Before [ShellController.start], so what
  /// the boot lands on is written too — as a replacement, since nobody pressed
  /// anything to get there.
  void attach() {
    shell.addressListenable.addListener(_onAddress);
    _subscription = _changes.listen(_onFragment);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose() {
    shell.addressListenable.removeListener(_onAddress);
    unawaited(_subscription?.cancel());
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  /// A person did something: the next move to another place is theirs.
  ///
  /// Called for every pointer and key going down. Public for the one press
  /// neither of those sees — a semantics action, which is what a click on a
  /// tappable becomes on a web page with semantics on: the engine withholds
  /// the pointer events and sends the action instead, so the pointer route
  /// hears nothing. Only the binding receives those, so the binding says so.
  void pressed() => _armed = true;

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) pressed();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) pressed();
    return false;
  }

  /// Decided in a microtask, after the event that moved the address: a
  /// keystroke reaches the focus system's handler before [_onKey], so a
  /// shortcut has already navigated by the time its key arms anything.
  void _onAddress() {
    if (_flushing) return;
    _flushing = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushing = false;
    var address = shell.address;
    // `fw:///`: the shell before anything has opened. Not a place to link to.
    if (address.space == null) return;
    if (address == _written) return;
    var push = _armed && _written != null && _written!.bare != address.bare;
    if (push) _armed = false;
    _written = address;
    (push ? _push : _replace)(fragmentOf(address));
  }

  /// The browser moved: back, forward, or an edited address bar. Its entry
  /// already exists, so this only ever replaces — to the canonical spelling of
  /// wherever the shell landed, which is also how a link naming nothing the
  /// shell knows stops showing in the bar.
  ///
  /// Disarms, too: a press left over from before the browser moved is not a
  /// reason to push whatever the panel restates on arrival over the forward
  /// entries.
  void _onFragment(String fragment) {
    _armed = false;
    if (addressOf(fragment) case var address?) shell.go(address);
    _written = shell.address;
    if (shell.address.space != null) _replace(fragmentOf(shell.address));
  }
}
