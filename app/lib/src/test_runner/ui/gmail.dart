import 'package:flutter_studio/internals/test_runner.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class Gmail extends StatefulWidget {
  final EmailInfo info;
  final Widget body;

  const Gmail({
    Key? key,
    required this.info,
    required this.body,
  }) : super(key: key);

  @override
  State<Gmail> createState() => _GmailState();
}

class _GmailState extends State<Gmail> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light().copyWith(colorScheme: _gmailColorScheme),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          leading: BackButton(),
          actions: [
            IconButton(onPressed: () {}, icon: Icon(Icons.archive_outlined)),
            IconButton(onPressed: () {}, icon: Icon(Icons.delete_outlined)),
            IconButton(
                onPressed: () {}, icon: Icon(Icons.mark_as_unread_outlined)),
            IconButton(onPressed: () {}, icon: Icon(Icons.more_horiz_outlined)),
          ],
        ),
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          }),
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15.0, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.info.subject,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      Icon(
                        Icons.star_outlined,
                        color: Colors.yellow.shade700,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15.0,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_circle,
                        size: 50,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.info.sender,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Flexible(
                                  child: Text(
                                    'to ${widget.info.recipient}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black54),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 12),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                          onPressed: () {}, icon: Icon(Icons.reply_outlined)),
                      IconButton(
                          onPressed: () {},
                          icon: Icon(Icons.more_horiz_outlined)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: widget.body,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

ColorScheme get _gmailColorScheme => ColorScheme.light(
      /// The color displayed most frequently across your app’s screens and components.
      primary: Colors.white,

      /// An accent color that, when used sparingly, calls attention to parts
      /// of your app.
      secondary: Colors.black,

      /// The background color for widgets like [Card].
      surface: Colors.white,

      /// A color that typically appears behind scrollable content.
      background: Colors.white,

      /// The color to use for input validation errors, e.g. for
      /// [InputDecoration.errorText].
      error: Colors.red,

      /// A color that's clearly legible when drawn on [primary].
      onPrimary: Colors.black87,
      onSecondary: Colors.black,
      onSurface: Colors.white,
      onBackground: Colors.white,
      onError: Colors.white,
    );
