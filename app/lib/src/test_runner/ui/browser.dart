import 'package:flutter/material.dart';

class Browser extends StatelessWidget {
  final Widget content;
  final String url;

  const Browser({
    super.key,
    required this.content,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Column(
        children: [
          Row(
            children: [
              Icon(Icons.arrow_back),
              Icon(Icons.arrow_forward),
              Icon(Icons.refresh),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.https),
                      Expanded(
                        child: SelectableText('https://url.com'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: content),
        ],
      );
    });
  }
}
