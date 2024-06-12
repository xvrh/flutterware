class FigmaLink {
  final String uri;
  final bool isFromCode;

  FigmaLink(this.uri, {this.isFromCode = false});

  factory FigmaLink.fromJson(Object? json) {
    return FigmaLink(json! as String);
  }

  @override
  bool operator ==(other) => other is FigmaLink && uri == other.uri;

  @override
  int get hashCode => uri.hashCode;

  String toJson() => uri;
}

class FigmaId {
  final String fileId;
  final String nodeId;

  FigmaId({required this.fileId, required this.nodeId});

  static FigmaId parse(FigmaLink link) {
    var parsed = Uri.parse(link.uri);
    if (parsed.host != 'www.figma.com') {
      throw Exception('Not recognized url host ${parsed.host}');
    }
    var fileId = parsed.pathSegments[1];
    var nodeId = parsed.queryParameters['node-id']!;
    return FigmaId(fileId: fileId, nodeId: nodeId);
  }
}
