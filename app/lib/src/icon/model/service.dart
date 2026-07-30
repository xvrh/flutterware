import '../../package_ref.dart';
import '../../utils/async_value.dart';
import 'icons.dart';

class IconService {
  static const previewSize = 70;

  final PackageRef package;
  late final _sample = AsyncValue<SampleIcon>(loader: _loadIcon);
  late AsyncValue<AppIcons> _icons;

  IconService(this.package) {
    _icons = AsyncValue(
      loader: () =>
          AppIcons.loadIcons(package.directory.path, size: previewSize),
      lazy: true,
    );
  }

  Future<SampleIcon> _loadIcon() async {
    var file = await AppIcons.findSampleIcon(
      package.directory.path,
      size: previewSize,
    );
    return SampleIcon(file);
  }

  AsyncValue<AppIcons> get icons => _icons;

  AsyncValue<SampleIcon> get sample => _sample;

  void dispose() {
    _icons.dispose();
    _sample.dispose();
  }
}

class SampleIcon {
  final AppIcon? file;

  SampleIcon(this.file);
}
