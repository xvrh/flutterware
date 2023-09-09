import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../third_party/device_frame/lib/device_frame.dart';
import 'app.dart';
import 'default_device_list.dart';
import 'parameters.dart';
import 'toolbar.dart';
import 'widget_book.dart';

class DetailView extends StatefulWidget {
  final TreeEntry entry;
  final dynamic value;
  final void Function(TreeEntry) onSelect;
  final WidgetBookAppState appState;

  const DetailView(
    this.entry,
    this.value, {
    super.key,
    required this.onSelect,
    required this.appState,
  });

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView>
    with ParametersMixin
    implements WidgetBookState {
  DeviceInfo? _device = Devices.ios.iPhoneSE;
  bool _visibleFrame = true;
  Orientation _orientation = Orientation.portrait;
  final _topBarPickers = <String, PickerState>{};
  bool _isDuringAppBuild = false;

  @override
  late final topBar = _TopBarAdapter(this);

  T _topBarPicker<T>(String name, Map<String, T> values, T defaultValue) {
    var pickers =
        _isDuringAppBuild ? widget.appState.topBarPickers : _topBarPickers;

    // TODO: depending if the call happens during the "appBuilder" build, store
    // the value higher-up to be saved accross views.
    if (!pickers.containsKey(name) ||
        !const DeepCollectionEquality().equals(pickers[name]!.values, values)) {
      pickers[name] = PickerState(values, defaultValue);
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        setState(() {});
      });
    }

    return (pickers[name]?.value as T?) ?? defaultValue;
  }

  @override
  Widget build(BuildContext context) {
    var book = WidgetBook.of(context);
    var value = widget.value;
    Widget mainWidget;
    if (value is Widget) {
      var widget = Builder(builder: (context) {
        _isDuringAppBuild = true;
        var app = book.appBuilder(
          context,
          Material(
            child: Center(
              child: value,
            ),
          ),
        );
        _isDuringAppBuild = false;
        return app;
      });

      if (_device case var device?) {
        mainWidget = DeviceFrame(
          device: device,
          isFrameVisible: _visibleFrame,
          orientation: _orientation,
          screen: widget,
        );
      } else {
        mainWidget = widget;
      }
    } else {
      mainWidget = Center(
        child: Text('Entry is not a widget. Type: ${value.runtimeType}'),
      );
    }

    mainWidget = WidgetBookStateProvider(state: this, child: mainWidget);

    var breadcrumbHeight = 40.0;
    var breadcrumb = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: SizedBox(
        height: breadcrumbHeight,
        child: Breadcrumb(widget.entry, onSelect: widget.onSelect),
      ),
    );
    var toolbar = Toolbar(
      children: [
        ToolbarDropdown<DeviceInfo?>(
          value: _device,
          items: {
            null: Text('None'),
            for (var device in defaultDevices.entries)
              device.key: Text(device.value)
          },
          onChanged: (v) {
            setState(() {
              debugDefaultTargetPlatformOverride = v?.identifier.platform;
              _device = v;
            });
          },
        ),
        if (_device != null) ...[
          ToolbarCheckbox(
            title: 'Frame:',
            value: _visibleFrame,
            onChanged: (v) {
              setState(() {
                _visibleFrame = v;
              });
            },
          ),
          ToolbarDropdown<Orientation>(
            value: _orientation,
            onChanged: (v) {
              setState(() {
                _orientation = v!;
              });
            },
            items: {
              Orientation.portrait: Text('Portrait'),
              Orientation.landscape: Text('Landscape'),
            },
          ),
        ],
        for (var picker
            in {...widget.appState.topBarPickers, ..._topBarPickers}.entries)
          ToolbarPicker(
            value: picker.value.value ?? picker.value.defaultValue,
            onChanged: (v) {
              setState(() {
                picker.value.value = v;
              });
            },
            title: Text(picker.key),
            items: {
              for (var v in picker.value.values.entries) v.value: Text(v.key)
            },
          ),
      ],
    );
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: Toolbar.height + breadcrumbHeight),
            Expanded(
              child: Container(child: mainWidget),
            )
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            breadcrumb,
            toolbar,
            Expanded(
              child: IgnorePointer(
                child: SizedBox(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopBarAdapter implements TopBarState {
  final _DetailViewState _state;

  _TopBarAdapter(this._state);

  @override
  T picker<T>(String name, Map<String, T> values, T defaultValue) {
    return _state._topBarPicker(name, values, defaultValue);
  }
}

class PickerState<T> {
  final Map<String, T> values;
  final T defaultValue;
  T? value;

  PickerState(this.values, this.defaultValue);
}

class Breadcrumb extends StatelessWidget {
  final TreeEntry entry;
  final void Function(TreeEntry) onSelect;

  const Breadcrumb(
    this.entry, {
    super.key,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var e in entry.breadcrumb) ...[
          InkWell(
            onTap: e == entry ? null : () => onSelect(e),
            child: Text(e.title),
          ),
          if (e != entry.breadcrumb.last) Icon(Icons.arrow_right)
        ]
      ],
    );
  }
}
