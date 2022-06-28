import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/ui/theme.dart';

void main() => runApp(AppThemeDemo());

class AppThemeDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Theme demo'),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(35),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    right: 0,
                    left: 0,
                    child: Container(
                      color: AppColors.tabDivider,
                      height: 1,
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Elements', height: 35),
                      Tab(text: 'Card', height: 35),
                      Tab(text: 'Third', height: 35),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: TabBarView(
            children: [
              _Tab1(),
              _Tab2(),
              Icon(Icons.directions_bike),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab1 extends StatefulWidget {
  @override
  _Tab1State createState() => _Tab1State();
}

class _Tab1State extends State<_Tab1> {
  late TextEditingController _disabledText;
  bool _checkbox1 = true;
  bool _switch1 = false;
  bool _switch2 = true;

  @override
  void initState() {
    super.initState();

    _disabledText = TextEditingController(text: 'Disabled field');
  }

  @override
  void dispose() {
    _disabledText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var textTheme = theme.textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 20,
          children: [
            Text('Text'),
            ElevatedButton(
              onPressed: () {},
              child: Text('Normal button'),
            ),
            ElevatedButton.icon(
              onPressed: () {},
              icon: Icon(Icons.access_alarm),
              label: Text('Icon button'),
            ),
            ElevatedButton(
              onPressed: null,
              child: Text('Disabled button'),
            ),
            OutlinedButton(
              onPressed: () {},
              child: Text('Secondary button'),
            ),
            OutlinedButton(
              onPressed: null,
              child: Text('Secondary disabled button'),
            ),
            TextButton(
              onPressed: () {},
              child: Text('Normal button'),
            ),
            IconButton(onPressed: () {}, icon: Icon(Icons.refresh)),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(child: Text('Reload')),
                PopupMenuItem(child: Text('Delete this item')),
              ],
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(child: Text('Reload')),
                PopupMenuItem(child: Text('Delete this item')),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('A menu', style: theme.textTheme.titleMedium,),
                  Icon(Icons.expand_more),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(primary: AppColors.stateError),
              onPressed: () {},
              child: Text('Danger button'),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Normal text field',
                  helperText: 'Helper text',
                  hintText: 'Hint',
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Text field',
                  errorText: 'With error',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  helperText: 'Helper text',
                  hintText: 'Hint',
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _disabledText,
                enabled: false,
              ),
            ),
            Checkbox(
              value: _checkbox1,
              onChanged: (_) {
                setState(() {
                  _checkbox1 = !_checkbox1;
                });
              },
            ),
            Checkbox(
              value: true,
              onChanged: null,
            ),
            Checkbox(
              value: false,
              onChanged: (_) {},
            ),
            CircularProgressIndicator(),
            Switch(
              value: _switch1,
              onChanged: (v) {
                setState(() {
                  _switch1 = v;
                });
              },
            ),
            Switch.adaptive(
              value: _switch2,
              onChanged: (v) {
                setState(() {
                  _switch2 = v;
                });
              },
            ),
            DropdownButton<int>(
              items: [
                DropdownMenuItem(value: 0, child: Text('First value')),
                DropdownMenuItem(value: 1, child: Text('Second value')),
              ],
              value: 0,
              onChanged: (v) {},
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                items: [
                  DropdownMenuItem(value: 0, child: Text('First value')),
                  DropdownMenuItem(value: 1, child: Text('Second value')),
                ],
                value: 0,
                onChanged: (v) {},
              ),
            ),
          ],
        ),
        for (var textSample in {
          'TextTheme.displayLarge': textTheme.displayLarge,
          'TextTheme.displayMedium': textTheme.displayMedium,
          'TextTheme.displaySmall': textTheme.displaySmall,
          'TextTheme.headlineLarge': textTheme.headlineLarge,
          'TextTheme.headlineMedium': textTheme.headlineMedium,
          'TextTheme.headlineSmall': textTheme.headlineSmall,
          'TextTheme.titleLarge': textTheme.titleLarge,
          'TextTheme.titleMedium': textTheme.titleMedium,
          'TextTheme.titleSmall': textTheme.titleSmall,
          'TextTheme.bodyLarge': textTheme.bodyLarge,
          'TextTheme.bodyMedium': textTheme.bodyMedium,
          'TextTheme.bodySmall': textTheme.bodySmall,
        }.entries)
          Text(
            textSample.key,
            style: textSample.value,
          ),
      ],
    );
  }
}

class _Tab2 extends StatelessWidget {
  const _Tab2();

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text('My table', style: theme.textTheme.titleSmall),
        ),
        Card(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A card',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DataTable(columns: [
                  DataColumn(label: Text('First')),
                  DataColumn(label: Text('Second'))
                ], rows: [
                  for (var i = 0; i < 3; i++)
                    DataRow(
                      cells: [
                        DataCell(Text('1 + $i')),
                        DataCell(Text('2 + $i')),
                      ],
                    ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
