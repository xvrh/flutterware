import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/previews.dart';

import 'onboarding_page.dart';
import 'onboarding_wave.dart';

/// **The developer's side.** Three pages, their content, their controls.
///
/// The editor authored `OnboardingPage`; this file is what a person writes to
/// use it. Nothing here is generated, and nothing here is a placeholder: the
/// last page holds a real `TextFormField` with a real controller and a real
/// validator, inside the animation.
///
/// Every page's entrance is driven by the `PageView`'s own offset — the current
/// page sits at `t = 1`, its neighbours at `t = 0`, and a swipe scrubs between
/// them. Nothing calls `play()`. That is `evaluate(t)` earning its keep: the
/// same component plays from a gesture here and from a frame counter in a video
/// renderer, with no second code path.
///
/// Two knobs: `language` swaps every string for its German equivalent, which is
/// 30–45% longer, and `page` parks the flow so a still can be taken mid-fuse.
@Preview(name: 'Onboarding', group: 'Motion', wrapper: wrapInDark)
Widget onboarding() => const _Onboarding();

Widget wrapInDark(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark(useMaterial3: true),
  home: child,
);

const _ink = Color(0xFF0C0913);

class _Copy {
  const _Copy({
    required this.left,
    required this.right,
    required this.subtitle,
  });

  final String left;
  final String right;
  final String subtitle;
}

const _english = [
  _Copy(
    left: 'Find your',
    right: 'morning',
    subtitle: 'Beans, roasters and brew guides, gathered in one quiet place.',
  ),
  _Copy(
    left: 'Brew it',
    right: 'better',
    subtitle: 'Timers, ratios and tasting notes that remember what worked.',
  ),
  _Copy(
    left: 'Start your',
    right: 'ritual',
    subtitle:
        'One account keeps your shelf, your notes and your timers in sync.',
  ),
];

const _german = [
  _Copy(
    left: 'Finde deinen',
    right: 'Morgen',
    subtitle: 'Bohnen, Röstereien und Brühanleitungen, gesammelt an einem ruhigen Ort.',
  ),
  _Copy(
    left: 'Brühe es',
    right: 'besser',
    subtitle: 'Timer, Verhältnisse und Verkostungsnotizen, die sich merken, was funktioniert hat.',
  ),
  _Copy(
    left: 'Beginne dein',
    right: 'Ritual',
    subtitle:
        'Ein Konto hält dein Regal, deine Notizen und deine Timer synchron.',
  ),
];

const _accents = [Color(0xFFFF8A4C), Color(0xFF4CC2FF), Color(0xFFB980FF)];

class _Onboarding extends StatefulWidget {
  const _Onboarding();

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _pages = PageController();
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  double _parked = 0;

  @override
  void dispose() {
    _pages.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Where the flow is, as a continuous number: 0.0 is page one, 1.5 is
  /// halfway between two and three.
  double get _offset => _pages.hasClients && _pages.position.haveDimensions
      ? _pages.page ?? _parked
      : _parked;

  @override
  Widget build(BuildContext context) {
    var german = context.knobs.picker('language', {
      'English': false,
      'Deutsch': true,
    }, false);
    var copy = german ? _german : _english;

    var wanted = context.knobs.double('page', 0, min: 0, max: 2);
    if (wanted != _parked) {
      _parked = wanted;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pages.hasClients) return;
        // Scrubbed, not paged: a fractional value parks the flow between two
        // pages so a still can be taken mid-transition, which is the only way
        // to look at the middle of an animation in a screenshot.
        _pages.jumpTo(wanted * _pages.position.viewportDimension);
      });
    }

    return Scaffold(
      backgroundColor: _ink,
      body: AnimatedBuilder(
        animation: _pages,
        builder: (context, _) {
          var offset = _offset;
          return Stack(
            fit: StackFit.expand,
            children: [
              PageView(
                controller: _pages,
                // `jumpTo` on paging physics snaps to the nearest page, so a
                // fractional park was silently rounded and the middle of the
                // transition could not be photographed at all. Scrubbing turns
                // the snapping off; swiping puts it back.
                physics: _parked == _parked.roundToDouble()
                    ? const PageScrollPhysics()
                    : const ClampingScrollPhysics(),
                children: [
                  for (var (index, page) in copy.indexed)
                    OnboardingPage(
                      progress: (1 - (offset - index).abs()).clamp(0.0, 1.0),
                      // Signed: negative while the page is still to the right
                      // and has not been reached, positive once it has been
                      // swiped past. The headline reads the sign to know which
                      // way it is already going.
                      travel: (offset - index).clamp(-1.0, 1.0),
                      accent: _accents[index],
                      image: AuroraImage(
                        seed: index * 977,
                        accent: _accents[index],
                      ),
                      titleLeft: page.left,
                      titleRight: page.right,
                      subtitle: page.subtitle,
                      action: index == copy.length - 1
                          ? _signUp(german)
                          : _continue(german, index),
                    ),
                ],
              ),
              Align(
                alignment: const Alignment(0, 0.965),
                child: _Dots(count: copy.length, offset: offset),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _continue(bool german, int index) => FilledButton(
    onPressed: () => _pages.nextPage(
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    ),
    style: FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    child: Text(german ? 'Weiter' : 'Continue'),
  );

  /// A real form inside a real animation: focus, keyboard and validation all
  /// work while the page is mid-entrance, because `Opacity` and `Transform`
  /// both hit-test through.
  Widget _signUp(bool german) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: german ? 'E-Mail-Adresse' : 'Email',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) {
            var text = value?.trim() ?? '';
            if (text.isEmpty) {
              return german ? 'Bitte E-Mail eingeben' : 'Enter your email';
            }
            if (!text.contains('@')) {
              return german
                  ? 'Das sieht nicht richtig aus'
                  : "That doesn't look right";
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _form.currentState?.validate(),
          style: FilledButton.styleFrom(
            backgroundColor: _accents[2],
            foregroundColor: _ink,
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(german ? 'Registrieren' : 'Sign up'),
        ),
      ],
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.offset});

  final int count;
  final double offset;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            // Continuous, not discrete: the width follows the swipe, so what
            // looks like a step is a number after all.
            width: 6 + 14 * (1 - (offset - i).abs()).clamp(0.0, 1.0),
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.25 + 0.55 * (1 - (offset - i).abs()).clamp(0.0, 1.0),
                ),
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
            ),
          ),
        ),
    ],
  );
}
