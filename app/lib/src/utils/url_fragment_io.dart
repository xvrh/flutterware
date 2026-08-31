/// See `url_fragment.dart` — off the web there is no address bar.
void writeUrlFragment(String fragment) {}

Stream<String> get urlFragmentChanges => const Stream.empty();
