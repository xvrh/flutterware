import 'package:flutter/foundation.dart';

import '../ui/tree_collapse.dart';

/// The scenario list's own state: what is folded away, and which selection the
/// tree has already been opened for.
///
/// Kept for the worktree's lifetime — see `ScenariosPlugin.browsingFor` —
/// rather than on the list pane's `State`, because the shell rebuilds that
/// pane from scratch every time you come back to the plugin. Both fields were
/// wrong there. A collapse was forgotten on the trip to another plugin, so
/// "collapse all" was something you re-clicked on every visit rather than a
/// shape you chose once; and [_revealedFor] went with it, so returning with a
/// scenario selected re-opened the branch you had closed after arriving —
/// which is the bug [revealSelection] documents, in a slower form.
///
/// Folders are tracked by what has been *closed*, not by what has been
/// opened: a file that appears after a rescan is then open like everything
/// around it, where an expanded-set would have hidden it until someone
/// thought to look.
class ScenarioBrowsing extends ChangeNotifier {
  final _closed = <String>{};

  bool isOpen(String branchId) => !_closed.contains(branchId);

  void toggle(String branchId) {
    if (!_closed.remove(branchId)) _closed.add(branchId);
    notifyListeners();
  }

  /// Whether anything is folded away at all, which is what makes one button
  /// enough for both directions.
  bool get anyClosed => _closed.isNotEmpty;

  void closeAll(Iterable<String> branchIds) {
    _closed.addAll(branchIds);
    notifyListeners();
  }

  void openAll() {
    if (_closed.isEmpty) return;
    _closed.clear();
    notifyListeners();
  }

  /// Whether the tree shows only what this branch changed. Off shows
  /// everything, with the changed rows tinted.
  bool get changedOnly => _changedOnly;
  var _changedOnly = false;
  set changedOnly(bool value) {
    if (value == _changedOnly) return;
    _changedOnly = value;
    notifyListeners();
  }

  /// Whether [foldIfCrowded] has anything left to decide — the cheap guard
  /// for a caller that would otherwise walk its whole tree twice on every
  /// build to ask a question already answered.
  bool get needsFoldDecision => !_decidedFold;

  /// Folds a suite that would not fit, once, the first time one is laid out.
  ///
  /// [rowCount] is what the tree would lay out open and [branchIds] is every
  /// branch in it. Over [treeRowBudget] rows, a suite opens as a table of
  /// contents rather than as a list you arrive already scrolling; under it,
  /// everything stays visible — most files here hold a scenario or two, and
  /// folding those trades a row for a click.
  ///
  /// Decided once, not re-applied. After this, the fold is whatever the
  /// person browsing made it, including all the way open. A branch that turns
  /// up later — a file written while the panel is open — is open in a folded
  /// tree, since the closed set names what existed when the decision was
  /// taken. Which is the right accident: the newest thing is the visible one.
  ///
  /// Deliberately without a notification. The caller is the build that
  /// lays the rows out and reads [isOpen] a few lines further down, so the
  /// answer is already used by the frame that asked for it. Notifying from
  /// inside a build is a `markNeedsBuild` during build, and deferring the
  /// decision to a post-frame callback instead would paint the crowded tree
  /// open for one frame before folding it.
  void foldIfCrowded(int rowCount, Iterable<String> branchIds) {
    // An empty tree is not a decision. The scan lands after the panel mounts,
    // so the first tree a cold panel lays out can be the one with nothing in
    // it yet, and deciding on that would mean never deciding at all.
    if (rowCount == 0 || _decidedFold) return;
    _decidedFold = true;
    if (!foldsOnArrival(rowCount)) return;
    _closed.addAll(branchIds);
  }

  var _decidedFold = false;

  /// Whether [key] is a selection the tree has not been opened for yet.
  bool needsReveal(String? key) => key != _revealedFor;

  /// Opens [branchIds] for a selection that has just arrived, once.
  ///
  /// An action taken once, not a rule applied on every build. Held open
  /// for as long as it is selected, the file around your selection cannot be
  /// closed at all: the click lands in [_closed], the row does not move, and
  /// the only visible effect anywhere is the collapse-all button quietly
  /// changing its mind. The catalog learned this the hard way — see
  /// `CatalogBrowsing.revealSelection`.
  void revealSelection(String? key, Iterable<String> branchIds) {
    if (key == _revealedFor) return;
    _revealedFor = key;
    var opened = false;
    for (var id in branchIds) {
      if (_closed.remove(id)) opened = true;
    }
    if (opened) notifyListeners();
  }

  String? _revealedFor;
}
