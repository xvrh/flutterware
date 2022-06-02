import 'package:collection/collection.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ui/side_bar.dart';

class TranslationsSidebar extends StatelessWidget {
  final List<Widget> children;

  const TranslationsSidebar({
    Key? key,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SideBar(
      header: Text('Translations'),
      child: ScrollConfiguration(
        //TODO(xha): renable the scrollbars. Currently there is a weird bug
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 4),
          children: children,
        ),
      ),
    );
  }
}

class TranslationKeyRow extends StatefulWidget {
  final ProjectInfo project;
  final TextInfo text;

  const TranslationKeyRow(this.project, this.text, {Key? key})
      : super(key: key);

  @override
  State<TranslationKeyRow> createState() => TranslationKeyRowState();
}

class TranslationKeyRowState extends State<TranslationKeyRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.text.translationKey,
              ),
              if (_expanded) _fontDetail(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fontDetail() {
    var text = widget.text;
    var rawColor = text.color;
    String? colorString;
    if (rawColor != null) {
      var color = Color(rawColor);
      colorString = '#${color.value.toRadixString(16)}';
    }
    var fontWeightRaw = text.fontWeight;
    String? fontWeightString;
    if (fontWeightRaw != null) {
      var fontWeight = FontWeight.values[fontWeightRaw];
      fontWeightString = fontWeight.toString().split('.').last;
    }
    var poEditorProject = widget.project.poEditorProjectId;

    return Container(
      color: Colors.black.withOpacity(0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('Family', text.fontFamily),
          _line('Size', text.fontSize?.toStringAsFixed(0)),
          _line('Color', colorString),
          _line('Weight', fontWeightString),
          _copyTextButton(),
          if (poEditorProject != null) _poEditorLink(poEditorProject),
        ].whereNotNull().toList(),
      ),
    );
  }

  Widget? _line(String key, String? value) {
    if (value != null && value.isNotEmpty) {
      return Row(
        children: [
          Expanded(child: Text(key)),
          Expanded(child: Text(value)),
        ],
      );
    }
    return null;
  }

  Widget _copyTextButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: OutlinedButton(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.text.text));
        },
        child: Text(
          'Copy text',
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  Widget _poEditorLink(int projectId) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: OutlinedButton(
        onPressed: () {
          //TODO(xha)
        },
        child: Text(
          'poeditor.com',
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
