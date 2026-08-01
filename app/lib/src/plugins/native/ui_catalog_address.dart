/// How Previews writes itself into an address, and how it reads itself
/// back out.
///
/// **Both directions in one file, on purpose.** The address is written by
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

/// A place in the catalog: a package, and an entry inside it if one is named.
class CatalogPlace {
  const CatalogPlace(this.package, {this.entryId});

  /// The workspace-relative package path — `app`, `examples/example`.
  final String package;

  /// The entry's id, which is `path/to/file.dart#symbol`. Null when the address
  /// names the package and stops there, which is where selecting the plugin off
  /// the rail leaves you.
  final String? entryId;

  @override
  bool operator ==(Object other) =>
      other is CatalogPlace &&
      other.package == package &&
      other.entryId == entryId;

  @override
  int get hashCode => Object.hash(package, entryId);

  @override
  String toString() => 'CatalogPlace($package${entryId ?? ''})';
}

/// The address segments naming [package] and, if given, [entryId].
///
/// The entry id is split on `/` rather than kept whole so the address stays
/// readable — `…/app/tool/catalog/demos/avatar.dart%23members` instead of one
/// percent-encoded blob. Only `#` ends up escaped, and that is the part a
/// reader most wants to see.
List<String> catalogSegments(String package, [String? entryId]) => [
  package,
  if (entryId != null && entryId.isNotEmpty) ...entryId.split('/'),
];

/// The inverse of [catalogSegments].
///
/// Joining the tail back with `/` is exactly the undo of splitting it, so an
/// entry id containing slashes survives however deep it is. Returns null for an
/// address that named no package at all.
CatalogPlace? catalogPlace(List<String> segments) {
  if (segments.isEmpty) return null;
  var entry = segments.skip(1).join('/');
  return CatalogPlace(segments.first, entryId: entry.isEmpty ? null : entry);
}

/// Whether the address has *moved*, and so has something new to ask of the
/// session.
///
/// The whole of a bug that took three attempts to find, so it is named rather
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
