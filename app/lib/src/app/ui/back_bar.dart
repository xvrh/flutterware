import 'package:flutter/material.dart';
import '../../utils/router_outlet.dart';

class BackBar extends StatelessWidget {
  final String text;
  final String url;

  const BackBar(this.text, {super.key, this.url = '..'});

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
