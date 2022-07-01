import 'package:flutter/material.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';

class BackBar extends StatelessWidget {
  final String text;
  final String url;

  const BackBar(this.text, {Key? key, this.url = '..'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          context.router.go(url);
        },
        icon: Icon(
          Icons.chevron_left,
          color: Colors.black54,
        ),
        label: Text(text),
      ),
    );
  }
}