import 'package:flutter/material.dart';
import '../third_party/device_frame/lib/device_frame.dart';
import 'app.dart';
import 'device_choice_panel.dart';
import 'figma/view.dart';
import 'parameters.dart';
import 'parameters_editor.dart';
import 'toolbar.dart';
import 'ui_catalog.dart';

class DetailView extends StatefulWidget {
  final TreeEntry entry;
  final dynamic value;
  final void Function(TreeEntry) onSelect;
  final UICatalogAppState appState;

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

class _DetailViewState extends State<DetailView> implements UICatalogState {
  final _deviceFrameKey = GlobalKey<__SingleDeviceWrapperState>();
  final _topBarPickers = <String, PickerParameter>{};
  Key _appKey = UniqueKey();
  final _knobsPanelKey = GlobalKey();
  bool _isDuringAppBuild = false;

  @override
  late final topBar = _TopBarAdapter(this);

  @override
  late final EditableParameters parameters = EditableParameters(
      onRefresh: _onRefreshParameter, onAdded: _onAddedParameter);

  T _topBarPicker<T>(String name, Map<String, T> options, T defaultValue) {
    var pickers =
        _isDuringAppBuild ? widget.appState.topBarPickers : _topBarPickers;

    var existingParameter = pickers[name];
    PickerParameter<T> parameter;
    if (existingParameter is PickerParameter<T>) {
      parameter = existingParameter;
    } else {
      if (existingParameter != null) {
        existingParameter.dispose();
        existingParameter = null;
      }

      parameter = PickerParameter(options: options);
      parameter.addListener(_onRefreshParameter);
    }

    pickers[name] = parameter
      ..defaultValue = defaultValue
      ..options = options;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {});
    });

    return parameter.value ?? parameter.defaultValue;
  }

  void _onRefreshParameter() {
    setState(() {
      _appKey = UniqueKey();
    });
  }

  void _onAddedParameter() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    var book = UICatalog.of(context);
    var value = widget.value;
    var device = widget.appState.deviceForEntry(widget.entry);

    Widget mainWidget;
    if (value is Widget) {
      var result = Builder(builder: (context) {
        _isDuringAppBuild = true;
        var app = book.appBuilder(
          context,
          Material(
            child: Center(
              key: _appKey,
              child: value,
            ),
          ),
        );
        _isDuringAppBuild = false;
        return app;
      });

      if (device.isEnabled) {
        if (device.useMosaic) {
          mainWidget = _Mosaic(mosaic: device.mosaic, child: result);
        } else {
          mainWidget = DeviceFrame(
            device: device.single.device,
            isFrameVisible: device.single.showFrame,
            orientation: device.single.orientation,
            screen: _SingleDeviceWrapper(
              key: _deviceFrameKey,
              child: result,
            ),
          );
        }
      } else {
        mainWidget = result;
      }
    } else {
      mainWidget = Center(
        child: Text('Entry is not a widget. Type: ${value.runtimeType}'),
      );
    }

    mainWidget = UICatalogStateProvider(state: this, child: mainWidget);

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
        ToolbarPanel(
          button: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Device'),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: device.isEnabled,
                  onChanged: (v) {
                    setState(() {
                      widget.appState.setDeviceForEntry(
                          widget.entry, device.copyWith(isEnabled: v));
                    });
                  },
                ),
              )
            ],
          ),
          panel: DeviceChoicePanel(
            choice: device,
            onChanged: (v) {
              setState(() {
                widget.appState.setDeviceForEntry(widget.entry, v);
              });
            },
          ),
        ),
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
              for (var v in picker.value.options.entries) v.value: Text(v.key)
            },
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        breadcrumb,
        toolbar,
        Expanded(
          child: FigmaView(
            entry: widget.entry,
            floatDefaultWidth: () {
              // TODO(xha): try to use _deviceFrameKey.currentState to get the
              // actual size of the element inside the phone frame
              return 300;
            },
            child: mainWidget,
          ),
        ),
        if (parameters.parameters.isNotEmpty) ...[
          Divider(),
          SizedBox(
            height: 200,
            child: ParametersEditor(parameters, key: _knobsPanelKey),
          ),
        ]
      ],
    );
  }
}

class _TopBarAdapter implements TopBarState {
  final _DetailViewState _state;

  _TopBarAdapter(this._state);

  @override
  T picker<T>(String name, Map<String, T> options, T defaultValue) {
    return _state._topBarPicker(name, options, defaultValue);
  }
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

class _Mosaic extends StatelessWidget {
  final Widget child;
  final MosaicDeviceChoice mosaic;

  const _Mosaic({
    required this.child,
    required this.mosaic,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: Wrap(
            children: [
              for (var orientation in mosaic.orientations)
                for (var device in mosaic.devices)
                  SizedBox(
                    width: 200,
                    child: DeviceFrame(
                      orientation: orientation,
                      device: device,
                      screen: child,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SingleDeviceWrapper extends StatefulWidget {
  final Widget child;
  const _SingleDeviceWrapper({super.key, required this.child});

  @override
  State<_SingleDeviceWrapper> createState() => __SingleDeviceWrapperState();
}

class __SingleDeviceWrapperState extends State<_SingleDeviceWrapper> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
