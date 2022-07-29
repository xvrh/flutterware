import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  testApp('Checkout', CheckoutTest());
}

class CheckoutTest extends AppTest {
  @override
  Future<void> run() async {
    var paymentService = MockPaymentService(); //    // External dependencies should be mocked

    // Pump the main app
    await pumpWidget(MyApp(paymentService: paymentService));
    await screenshot();

    // Press the button to go to the cart
    await tap('Go to cart'); // Recommendation: in real project, don't hardcode the target text but use your translation system.
    await screenshot(name: 'Cart');

    await tap(find.byIcon(Icons.delete).at(1));
    await screenshot(name: 'Removed item');

    // Setup the service mock result
    var payResult = Completer<bool>();
    paymentService.payResult = payResult.future;

    await tap('Pay', pumpFrames: false); // pumpFrames: false is needed because there is an infinite loading animation
    await pump();
    await pump(Duration(milliseconds: 500)); // Move the CircularProgress animation
    await screenshot();

    // Exercise the happy path (payment succeed and the error path)
    await splitTest({
      'Happy path': () async {
        payResult.complete(true);
        await pump();
        await pump(Duration(seconds: 1));
        await screenshot();
      },
      'Error on payment': () async {
        payResult.complete(false);
        await pump();
        await pump(Duration(seconds: 1));
        await screenshot();
      },
    });
  }
}

// ====================================================
// Bellow this line it is a fake app used to demonstrate the test API
// You should just delete this code and use your own app

class MyApp extends StatelessWidget {
  final PaymentService paymentService;

  MyApp({super.key, PaymentService? paymentService})
      : paymentService = paymentService ?? PaymentService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _HomePage(),
    );
  }

  static MyApp of(BuildContext context) =>
      context.findAncestorWidgetOfExactType<MyApp>()!;
}

class _HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home page'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'My app',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => _CheckoutPage()));
            },
            icon: Icon(Icons.shopping_cart),
            label: Text('Go to cart'),
          ),
        ],
      ),
    );
  }
}

class _CheckoutPage extends StatefulWidget {
  @override
  State<_CheckoutPage> createState() => __CheckoutPageState();
}

class __CheckoutPageState extends State<_CheckoutPage> {
  final _cart = <String>['1 bottle of milk', '2 apples'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cart'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (var article in _cart)
                    ListTile(
                      title: Text(article),
                      trailing: IconButton(
                        onPressed: () {
                          setState(() {
                            _cart.remove(article);
                          });
                        },
                        icon: Icon(Icons.delete),
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pay,
              icon: Icon(Icons.payment),
              label: Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }

  void _pay() async {
    var paymentService = MyApp.of(context).paymentService;

    var loader = OverlayEntry(
      builder: (context) => Container(
        color: Colors.black38,
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          color: Colors.red,
        ),
      ),
    );
    Overlay.of(context)!.insert(loader);
    var result = await paymentService.pay();
    loader.remove();

    if (result) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Payment accepted'),
          content: Text('😀', style: const TextStyle(fontSize: 100, color: Colors.green,),),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Payment refused'),
          content: Icon(Icons.error, size: 100),
        ),
      );
    }
  }
}

class PaymentService {
  Future<bool> pay() async => true;
}

/// A mock class where we can control the result of the external code
/// Probably use package:mockito (https://pub.dev/packages/mockito) in a real project.
class MockPaymentService implements PaymentService {
  Future<bool> payResult = Future.value(true);

  @override
  Future<bool> pay() async {
    return payResult;
  }
}
