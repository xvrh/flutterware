import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.white,
        //appBarTheme: AppBarTheme(
        //  color: Colors.white,
        //  titleTextStyle: TextStyle(color: Colors.black87),
        //  elevation: 1,
        //  scrolledUnderElevation: 2,
        //),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
        ), 
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: [
        Locale('en'),
        Locale('fr'),
        Locale('es'),
        Locale('de'),
      ],
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        children: [
          Text('Language: ${Localizations.localeOf(context).languageCode}'),
          Text(MaterialLocalizations.of(context).alertDialogLabel),
          Text(MaterialLocalizations.of(context).invalidTimeLabel),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  'You have pushed the button this many times: and this need',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headline6,
                ),
              ),
              Text(
                '$_counter',
                style: Theme.of(context).textTheme.headline2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          Divider(),
          TextField(
            decoration: InputDecoration(
              suffixIcon: Icon(Icons.access_alarm),
              prefixIcon: Icon(Icons.password),
            ),
          ),
          Switch(value: true, onChanged: (v) {}),
          ElevatedButton(onPressed: () {}, child: Text('OK')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
