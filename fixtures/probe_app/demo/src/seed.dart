/// What a dev launch should put in the app before anybody touches it.
///
/// Here rather than in `lib/` on purpose: this is the shape a project takes
/// when its dev-only entry points and the things only they use are kept out of
/// what ships. An enum in this position has no `package:` URI, so a wrapper
/// naming it has to name it by path — which is what makes it the test case.
enum Seed { empty, oneOrder, full }
