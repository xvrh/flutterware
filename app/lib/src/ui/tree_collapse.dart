/// How many rows a browser column shows before you arrive already scrolling.
///
/// Both trees this governs — the scenario suite and the preview catalog — lay
/// 26-pixel rows out in a 240-pixel column, so thirty of them is around 780
/// pixels: a paneful at an ordinary window height, header and filter field
/// taken off.
///
/// A constant rather than something read off a `LayoutBuilder` on purpose.
/// The decision it answers is taken once, the first time a tree is laid out,
/// and keying it to whatever height the window happened to have at that
/// instant would give the same project a different first impression on a
/// laptop and on a monitor — for a fold nothing would ever undo, since the
/// decision is not revisited when the window is resized.
const treeRowBudget = 30;

/// Whether a tree of [rowCount] rows should open with everything folded away.
///
/// Folded is the better arrival only for a suite that does not fit. A closed
/// row carries the count of what is behind it, so a long tree folds into a
/// table of contents; a short one folds into a row per click, which costs a
/// click and reveals nothing that was not already on screen.
bool foldsOnArrival(int rowCount) => rowCount > treeRowBudget;
