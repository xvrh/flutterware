/// Where a frame is, and how to read it.
///
/// Raw pixels carry no header, so a path on its own is not enough to draw:
/// the width and height have to travel with it. A preview's frame is filed in
/// the `ShotCache`, which keeps a record beside every entry; a scenario's is
/// written by the replay, which records the dimensions in the step rather than
/// beside the file. This is what makes the second one openable by anything that
/// was not there when it ran.
class FrameRef {
  const FrameRef({
    required this.path,
    required this.width,
    required this.height,
  });

  static FrameRef? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    var path = json['path'] as String?;
    if (path == null) return null;
    return FrameRef(
      path: path,
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
    );
  }

  final String path;
  final int width;
  final int height;

  bool get isDrawable => width > 0 && height > 0;

  Map<String, Object?> toJson() => {
    'path': path,
    'width': width,
    'height': height,
  };
}
