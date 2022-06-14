import 'package:flutter/foundation.dart';

import '../project.dart';
import '../utils/async_value.dart';
import 'icons.dart';

class IconService {
  static const _previewSize = 50;

  final Project project;
  late final _sample = AsyncValue<SampleIcon>(loader: _loadIcon);
  late AsyncValue<AppIcons> _icons;

  IconService(this.project) {
    _icons = AsyncValue(
        loader: () =>
            AppIcons.loadIcons(project.directory.path, size: _previewSize),
        lazy: true);
  }

  Future<SampleIcon> _loadIcon() async {
    var file = await AppIcons.findSampleIcon(project.directory.path,
        size: _previewSize);
    return SampleIcon(file);
  }

  AsyncValue<AppIcons> get icons => _icons;

  ValueListenable<Snapshot<SampleIcon>> get sample => _sample;

  void dispose() {
    _icons.dispose();
    _sample.dispose();
  }
}

class SampleIcon {
  final AppIcon? file;

  SampleIcon(this.file);
}
