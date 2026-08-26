/// Two names, in the order a reader scans them.
///
/// Case-insensitive first, so `README.md` sits among its neighbours rather
/// than above every lowercase path; the case-sensitive comparison breaks the
/// tie, so `Foo` and `foo` never swap places between two rebuilds of the same
/// tree.
///
/// Shared by every tree that draws names, because two trees in one window that
/// disagree about where `README.md` goes are two trees a reader has to learn
/// separately.
int compareNames(String a, String b) {
  var folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded != 0 ? folded : a.compareTo(b);
}
