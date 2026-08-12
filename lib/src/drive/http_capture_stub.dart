/// No-op for platforms without `dart:io` — a web app has no `HttpClient` and
/// no VM http profile to feed.
void armHttpCapture() {}
