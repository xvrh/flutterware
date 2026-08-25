/// How Previews writes itself into an address, and how it reads itself
/// back out.
///
/// Both directions in one file, on purpose. The address is written by
/// search (so a hit is somewhere real), by the tree (so clicking an entry is
/// navigation), and by whoever pastes one; it is read by the panel deciding
/// what to show. If encode and decode lived apart they would drift, and the
/// symptom of drift here is the worst kind: the app navigates, nothing throws,
/// and you land on the wrong demo.
///
/// The round trip is the contract — [catalogSegments] and [catalogPlace] are
/// inverses, and there is a test that says so. That is also what keeps the
/// write-back from looping: a panel that writes the address it just read
/// produces a byte-identical address, which the shell recognises as no move at
/// all.
library;

/// A place in the catalog: a package, and inside it either one entry or the
/// part of the tree being looked at.
///
/// **Three states, told apart by a `#`.** An entry id is
/// `path/to/file.dart#symbol` and always has one; anything else after the
/// package is a *path prefix* — a directory, or a single file whose variants
/// are wanted. That is a discriminator rather than a convention: no directory
/// can contain a `#` in an entry id's position, so nothing has to be escaped
/// and nothing is ambiguous.
///
/// Deliberately a path prefix rather than a branch of the tree. A branch's id
/// is a path of *labels* — real directories below the common prefix, then
/// whatever `@Preview(group:)` said — which would be a second namespace living
/// in the same slot as the first. Truncating a real entry address is how a
/// person reaches this state, so what they land on has to be something a real
/// entry address contains.
class CatalogPlace {
  const CatalogPlace(this.package, {this.entryId, this.directory});

  /// The workspace-relative package path — `app`, `examples/example`.
  final String package;

  /// The entry's id, which is `path/to/file.dart#symbol`. Null when the address
  /// names the package and stops there, which is where selecting the plugin off
  /// the rail leaves you.
  final String? entryId;

  /// What the catalog is narrowed to — `tool/catalog/demos`, or one file. Null
  /// when the whole package is being shown, which is the whole index.
  ///
  /// **A selection, which is why it belongs in the address.** Picking a folder
  /// in the tree shows that folder and nothing else; the way out is the row
  /// above every folder. It is a place, so it can be linked to and come back
  /// to — unlike a scroll position, which is what this briefly became and why
  /// it stopped being written.
  ///
  /// It also settles the address bar's own invitation to truncate at a middle
  /// segment. That used to answer `No entry "tool/catalog/demos" in this
  /// package`; it is now the folder, which is what somebody truncating an entry
  /// address is reaching for.
  ///
  /// Never set at the same time as [entryId]: an address names one place, and
  /// an entry already says which file it is in.
  final String? directory;

  /// The tail either of them puts in the address.
  String? get path => entryId ?? directory;

  /// Whether [entryPath] is inside [directory] — the whole of what narrowing
  /// means. A file scope matches the entries declared in it; a directory scope
  /// matches everything below it.
  bool covers(String entryPath) => scopeCovers(directory, entryPath);

  @override
  bool operator ==(Object other) =>
      other is CatalogPlace &&
      other.package == package &&
      other.entryId == entryId &&
      other.directory == directory;

  @override
  int get hashCode => Object.hash(package, entryId, directory);

  @override
  String toString() => 'CatalogPlace($package${path ?? ''})';
}

/// The address segments naming [package] and, if given, [entryId].
///
/// The entry id is split on `/` rather than kept whole so the address stays
/// readable — `…/app/tool/catalog/demos/avatar.dart%23members` instead of one
/// percent-encoded blob. Only `#` ends up escaped, and that is the part a
/// reader most wants to see.
/// [path] is an entry id or a directory — see [CatalogPlace]. Both serialise
/// the same way, which is the point: one slot, one split, and which of the two
/// it is comes back out of the `#`.
List<String> catalogSegments(String package, [String? path]) => [
  package,
  if (path != null && path.isNotEmpty) ...path.split('/'),
];

/// The inverse of [catalogSegments].
///
/// Joining the tail back with `/` is exactly the undo of splitting it, so an
/// entry id containing slashes survives however deep it is. Returns null for an
/// address that named no package at all.
CatalogPlace? catalogPlace(List<String> segments) {
  if (segments.isEmpty) return null;
  var tail = segments.skip(1).join('/');
  if (tail.isEmpty) return CatalogPlace(segments.first);
  return tail.contains('#')
      ? CatalogPlace(segments.first, entryId: tail)
      : CatalogPlace(segments.first, directory: tail);
}

/// Whether the address has *moved*, and so has something new to ask of the
/// session.
///
/// This was a bug that took three attempts to find, so it is named rather
/// than left inline. `didChangeDependencies` fires for its own reasons, not
/// only when the address changes; and the address lags a local selection by a
/// frame, because its write-back is a post-frame callback. Handing it over
/// unconditionally therefore pushes the entry you came *from* onto a session
/// that has already moved on, and the session dutifully switches back to it —
/// a click silently undone.
///
/// It was harmless for as long as nothing else wrote the session's wanted
/// entry, because the setter absorbed the repeat. The moment selecting also
/// counted as wanting, the repeat became a real change and undid every click
/// rather than an unlucky half of them.
///
/// [followed] is what was last handed over; [hasFollowed] tells a first call
/// apart from one that handed over null, and [sessionChanged] forces it because
/// a session that has just been created has been told nothing at all.
bool addressMoved({
  required bool hasFollowed,
  required bool sessionChanged,
  required String? followed,
  required String? place,
}) => !hasFollowed || sessionChanged || place != followed;

/// Whether [entryPath] is inside [scope] — null being the whole package.
///
/// The rule the sheet narrows by, and the same one [CatalogPlace.covers]
/// answers with: a file scope matches the entries declared in it, a directory
/// scope matches everything below it, and a scope that is merely a prefix of
/// the *name* — `demo/team` against `demo/teamwork/x.dart` — matches nothing.
bool scopeCovers(String? scope, String entryPath) {
  if (scope == null) return true;
  return entryPath == scope || entryPath.startsWith('$scope/');
}
