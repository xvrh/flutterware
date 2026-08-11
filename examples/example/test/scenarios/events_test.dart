import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:logging/logging.dart';

/// What the app did between two screens — the transition events the panel
/// shows on the arrow, and the Events tab lists in full.
///
/// Three lanes are automatic and need no code at all: `print`, every
/// `package:logging` record, and every platform channel message a plugin
/// sends. The fourth is this file's subject — an in-process fake reporting
/// itself, which is the only way the runner can know about work that never
/// leaves the isolate.
void main() {
  scenario('Signing in', (s) async {
    await s.pumpWidget(const _SignInApp(_FakeApi()));

    await s.enterText(TextField, 'nobody@example.com');
    await s.tap('Sign in');

    await s.screen('Signed in');
    expect(find.text('Hello, nobody@example.com'), findsOneWidget);
  });
}

/// A fake the app is built with — the shape a real project's test doubles
/// have, with two lines added so the flow shows what it did.
///
/// `recordScenarioEvent` is a no-op outside a scenario run, so these calls
/// cost a bare `flutter test` nothing and can live in shared fakes for good.
class _FakeApi {
  const _FakeApi();

  Future<String> signIn(String email) async {
    recordScenarioEvent(
      ScenarioEvent.request(
        method: 'POST',
        url: '/sessions',
        status: 200,
        data: {'email': email},
      ),
    );
    recordScenarioEvent(
      ScenarioEvent.query(
        sql: 'INSERT INTO sessions (email) VALUES (?)',
        args: [email],
        rows: 1,
      ),
    );
    recordScenarioEvent(
      ScenarioEvent.analytics('sign_in', params: {'method': 'password'}),
    );
    return email;
  }
}

final _log = Logger('sign-in');

class _SignInApp extends StatefulWidget {
  const _SignInApp(this.api);

  final _FakeApi api;

  @override
  State<_SignInApp> createState() => _SignInAppState();
}

class _SignInAppState extends State<_SignInApp> {
  final _email = TextEditingController();
  String? _user;

  Future<void> _signIn() async {
    _log.info('signing in as ${_email.text}');
    var user = await widget.api.signIn(_email.text);
    setState(() => _user = user);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_user case var user?)
                Text('Hello, $user', style: const TextStyle(fontSize: 20))
              else ...[
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _signIn, child: const Text('Sign in')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
