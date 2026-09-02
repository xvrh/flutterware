/// Lets app code announce work that finishes on the real event loop, so a
/// scenario's next verb waits for it rather than photographing a placeholder.
/// See [RealWork].
library;

export 'src/real_work/tracker.dart' show RealWork, TrackedRealWork;
