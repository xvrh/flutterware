import 'dart:async';
import 'package:flutter/material.dart';
import 'devbar.dart';
import 'plugins/variables/plugin.dart';

class FeatureFlag<T> {
  final String name;
  final String? description;

  final T _defaultValue;

  FeatureFlag(this.name, this._defaultValue,
      {this.description, bool? addToDevbar})
      : assert(T != dynamic && T != Null);

  FeatureFlagValue<T> withValue(T newValue) =>
      FeatureFlagValue<T>(this, newValue);

  FeatureFlagValue<T> get withDefaultValue => withValue(_defaultValue);

  T dependsOnValue(BuildContext context) {
    var holder = context.dependOnInheritedWidgetOfExactType<FeatureFlags>();
    if (holder != null) {
      var flagValue = holder.find(this);
      if (flagValue != null) {
        return flagValue._value;
      }
    }
    return _defaultValue;
  }

  T findValue(BuildContext context) {
    var holder = context.findAncestorWidgetOfExactType<FeatureFlags>();
    if (holder != null) {
      var flagValue = holder.find(this);
      if (flagValue != null) {
        return flagValue._value;
      }
    }
    return _defaultValue;
  }

  @override
  String toString() => 'FeatureFlag<$T>($name, value: $_defaultValue)';
}

class FeatureFlagValue<T> {
  final FeatureFlag flag;
  final T _value;

  FeatureFlagValue(this.flag, this._value);

  @override
  String toString() => 'FeatureFlagValue<$T>(${flag.name}, value: $_value)';
}

class FeatureFlags extends InheritedWidget {
  final Map<FeatureFlag, FeatureFlagValue> values;

  FeatureFlags._({required Widget child, required this.values})
      : super(child: child);

  static Widget merge({
    required Widget child,
    required List<FeatureFlagValue> flags,
  }) {
    return Builder(
      builder: (context) {
        var parent = context.dependOnInheritedWidgetOfExactType<FeatureFlags>();
        return FeatureFlags._(
          values: {
            if (parent != null) ...parent.values,
            for (var flag in flags) flag.flag: flag,
          },
          child: child,
        );
      },
    );
  }

  FeatureFlagValue<T>? find<T>(FeatureFlag<T> flag) {
    return values[flag] as FeatureFlagValue<T>?;
  }

  @override
  bool updateShouldNotify(covariant FeatureFlags oldWidget) {
    return true;
  }
}

class FeatureFlagDevbar extends StatelessWidget {
  final Widget child;

  const FeatureFlagDevbar({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var devbar = context.findAncestorWidgetOfExactType<Devbar>()!;
    return FeatureFlags.merge(
      child: _FlagToVariable(child: child),
      flags: devbar.flags,
    );
  }
}

class _FlagToVariable extends StatefulWidget {
  final Widget child;

  const _FlagToVariable({Key? key, required this.child}) : super(key: key);

  @override
  _FlagToVariableState createState() => _FlagToVariableState();
}

class _FlagToVariableState extends State<_FlagToVariable> {
  final _flagValues = <FeatureFlag, FlagRegistration>{};
  late DevbarState _devbar;

  @override
  void initState() {
    super.initState();
    _devbar = DevbarState.of(context);
  }

  @override
  Widget build(BuildContext context) {
    var parentFlags =
        context.dependOnInheritedWidgetOfExactType<FeatureFlags>()!;

    var alreadyRegistered = {..._flagValues};
    for (var flag in parentFlags.values.values) {
      _register(flag);
      alreadyRegistered.remove(flag.flag);
    }
    for (var oldVariable in alreadyRegistered.values) {
      _unregister(oldVariable);
    }

    return FeatureFlags.merge(
      flags: _flagValues.values.map((v) => v.value).toList(),
      child: widget.child,
    );
  }

  void _register(FeatureFlagValue flagValue) {
    var flag = flagValue.flag;

    if (_flagValues.containsKey(flag)) {
      return;
    }

    DevbarVariable? variable;
    StreamSubscription? variableSubscription;
    if (flagValue is FeatureFlagValue<bool>) {
      variable = _devbar.variables.checkbox(flag.name,
          description: flag.description, defaultValue: flagValue._value);
    }

    if (variable != null) {
      flagValue = flag.withValue(variable.currentValue);
      variableSubscription = variable.value.listen((newValue) {
        setState(() {
          _flagValues[flag]!.value = flag.withValue(newValue);
        });
      });
    }
    _flagValues[flag] = FlagRegistration(flagValue,
        variable: variable, variableSubscription: variableSubscription);
  }

  void _unregister(FlagRegistration registration) {
    var variable = registration.variable;
    if (variable != null) {
      _devbar.variables.remove(variable);
    }
    var variableSubscription = registration.variableSubscription;
    if (variableSubscription != null) {
      variableSubscription.cancel();
    }
  }

  @override
  void dispose() {
    for (var variable in _flagValues.values) {
      _unregister(variable);
    }
    super.dispose();
  }
}

class FlagRegistration {
  final DevbarVariable? variable;
  final StreamSubscription? variableSubscription;
  FeatureFlagValue value;

  FlagRegistration(this.value, {this.variable, this.variableSubscription});
}
