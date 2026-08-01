/// Which device bucket an entry is shown in by the in-app `UICatalog`.
///
/// The catalog widget's own vocabulary, and only its own. It used to be an
/// annotation field as well — `@Demo(formFactor:)`, carrying a `Size` that
/// `transform()` folded into `Preview.size` — and both of those went with the
/// annotation. What is left is what the widget always did with it: pick a frame
/// from `default_device_list.dart`.
///
/// [all] states no opinion, and is the default for an entry no picker matches.
enum FormFactor { mobile, desktop, all }
