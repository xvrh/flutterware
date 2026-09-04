// The widgets this app's scenes may place, declared once.
//
// This is the file that stands in for resolving the package. The editor
// never compiles the app, so it cannot discover that `DrinkBadge` takes a
// `double size` — it is told here, and everything downstream follows: the
// generated `DrinkBadgeArgs` a scene file spells, the type the inspector
// shows, and the refusal for an argument the widget does not have.
//
// It is also the only place in the system that names an argument with a
// string, by decision: written by hand, it has to compile before anything
// has been generated from it, so it mentions nothing generated.
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_example/shop/shop_app.dart' as app;

final sceneExternals = [
  ExternalWidget(
    'DrinkBadge',
    args: [const Arg<double>('size', 56)],
    build: (a) => app.DrinkBadge(app.drinks[1], size: a.number('size') ?? 56),
  ),
  ExternalWidget(
    'Spinner',
    args: [const Arg<double>('size', 36)],
    build: (a) => app.Spinner(size: a.number('size') ?? 36),
  ),
  ExternalWidget(
    'OrderButton',
    args: [const Arg<String>('label', 'Order now')],
    build: (a) => app.OrderButton(label: a.text('label') ?? 'Order now'),
  ),
];
