import 'package:flutter/material.dart';
import '../../ui_book/parameters.dart';
import '../../ui_book/parameters_editor.dart';
import '../devbar.dart';
import '../ui/button.dart';
import '../ui/service.dart';

typedef DevbarKnobs = Parameters;

class AddDevbarKnobs extends StatefulWidget {
  final Widget Function(BuildContext, DevbarKnobs) builder;
  final BuildContext? context;

  const AddDevbarKnobs({super.key, required this.builder, this.context});

  @override
  State<AddDevbarKnobs> createState() => _AddDevbarKnobsState();
}

class _AddDevbarKnobsState extends State<AddDevbarKnobs> {
  late final _knobs =
      EditableParameters(onRefresh: _refresh, onAdded: _refresh);

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    var child = widget.builder(context, _knobs);

    if (Devbar.of(context) != null) {
      return AddDevbarButton(
        position: DevbarButtonPosition.topRight,
        button: DevbarIcon(
          onTap: () {
            showBottomSheet(
              context: widget.context ?? context,
              builder: (context) => _BottomSheet(
                parameters: _knobs,
              ),
            );
          },
          icon: Icons.settings,
        ),
        child: child,
      );
    } else {
      return child;
    }
  }

  @override
  void dispose() {
    _knobs.dispose();
    super.dispose();
  }
}

class _BottomSheet extends StatelessWidget {
  final EditableParameters parameters;

  const _BottomSheet({required this.parameters});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height / 3,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        border: Border(top: BorderSide(width: 2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SizedBox()),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Close'),
              ),
            ],
          ),
          Expanded(
            child: ParametersEditor(parameters),
          ),
        ],
      ),
    );
  }
}
