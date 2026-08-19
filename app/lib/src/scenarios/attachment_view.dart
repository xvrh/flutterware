import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/scenarios/notification.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../previews/devices.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'artifacts.dart';
import 'framed_shot.dart';

/// An attachment as a beat of the story: what the flow canvas draws between
/// two screens, and what the detail page blows up.
///
/// A notification is drawn as the recipient's phone would show it — a banner
/// dropped over the screen it arrived on. Everything else is a document: a
/// paper sheet carrying its content where the format allows (text renders,
/// images show) and its identity where it does not.
class ScenarioAttachmentShot extends StatelessWidget {
  const ScenarioAttachmentShot({
    super.key,
    required this.attachment,
    required this.background,
    required this.device,
    required this.statusFallback,
    this.appLabel,
    this.appIcon,
  });

  final ScenarioRunAttachment attachment;

  /// The step whose screen the attachment arrived over — the previous step
  /// for one that rode a capture, the last step for one that trailed the
  /// run. Null when there was no screen yet, which draws a lock-screen-ish
  /// blank instead.
  final ScenarioRunStep? background;

  final Device? device;
  final Brightness statusFallback;

  /// What the banner calls the app when the payload does not say — the
  /// project's own name, when the caller knows it.
  final String? appLabel;

  /// The project's launcher icon, when the host could find one — see
  /// [NotificationBanner.appIcon].
  final ImageProvider? appIcon;

  @override
  Widget build(BuildContext context) {
    if (attachment.mimeType == ScenarioNotification.mimeType) {
      return _NotificationShot(
        attachment: attachment,
        background: background,
        device: device,
        statusFallback: statusFallback,
        appLabel: appLabel,
        appIcon: appIcon,
      );
    }
    // On the device's own canvas, so the sheet scales in proportion to the
    // phones beside it on the strip — bare, it was fitted to the cell and
    // came out wider than the screens it sat between.
    var canvas = Size(device?.width ?? 800, device?.height ?? 600);
    var width = canvas.width * 0.86;
    return SizedBox(
      width: canvas.width,
      height: canvas.height,
      child: Center(
        child: _DocumentSheet(
          attachment: attachment,
          width: width,
          height: math.min(width * 1.35, canvas.height * 0.9),
        ),
      ),
    );
  }
}

/// The banner over the screen it arrived on — or over a dark lock screen
/// when it arrived before the flow drew anything.
class _NotificationShot extends StatelessWidget {
  const _NotificationShot({
    required this.attachment,
    required this.background,
    required this.device,
    required this.statusFallback,
    required this.appLabel,
    required this.appIcon,
  });

  final ScenarioRunAttachment attachment;
  final ScenarioRunStep? background;
  final Device? device;
  final Brightness statusFallback;
  final String? appLabel;
  final ImageProvider? appIcon;

  @override
  Widget build(BuildContext context) {
    var artifacts = ScenarioArtifactsScope.of(context);
    return FutureBuilder<Uint8List?>(
      future: artifacts.readBytes(attachment.file),
      builder: (context, snapshot) {
        var notification = snapshot.data == null
            ? null
            : ScenarioNotification.decode(snapshot.data!);
        if (snapshot.connectionState == ConnectionState.done &&
            notification == null) {
          // Claimed the mimeType, was not one — the sheet tells the truth.
          return _DocumentSheet(attachment: attachment);
        }
        // Dark runs got light status icons; the banner follows the run.
        var dark = statusFallback == Brightness.light;
        var overlay = Stack(
          fit: StackFit.expand,
          children: [
            // The dim that says "this moment is about the banner" — the
            // screen stays legible under it, the way a real notification
            // leaves the app visible.
            Container(color: Colors.black.withValues(alpha: 0.3)),
            if (notification != null)
              Positioned(
                top: (device?.insetTop ?? 0) + 8,
                left: 8,
                right: 8,
                child: NotificationBanner(
                  notification: notification,
                  appLabel: appLabel,
                  appIcon: appIcon,
                  dark: dark,
                ),
              ),
          ],
        );
        if (background case var step?) {
          return FramedShot(
            step: step,
            device: device,
            fallbackBrightness: statusFallback,
            screenOverlay: overlay,
          );
        }
        // No screen yet: the phone was locked, which is where a real one
        // lands anyway.
        var size = Size(device?.width ?? 390, device?.height ?? 844);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFF15151A),
                alignment: Alignment.topCenter,
                padding: EdgeInsets.only(top: (device?.insetTop ?? 0) + 40),
                child: Text(
                  '9:41',
                  style: TextStyle(
                    fontSize: 68,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.9),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (notification != null)
                Positioned(
                  top: (device?.insetTop ?? 0) + 140,
                  left: 8,
                  right: 8,
                  child: NotificationBanner(
                    notification: notification,
                    appLabel: appLabel,
                    appIcon: appIcon,
                    dark: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A real-looking notification banner, drawn in the screen's own logical
/// coordinates — dev_studio's trick, back on the attachment system.
///
/// Everything the payload leaves out is supplied here: the icon tile, the
/// "now", the light/dark chrome. Fully explicit text styles because the
/// banner floats over the app's pixels, outside any Material.
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({
    super.key,
    required this.notification,
    required this.dark,
    this.appLabel,
    this.appIcon,
  });

  final ScenarioNotification notification;
  final String? appLabel;

  /// The project's real launcher icon, when the host could find one — the
  /// panel can, an exported page cannot. Falls back to the initial tile,
  /// including when the image itself fails to load.
  final ImageProvider? appIcon;

  final bool dark;

  @override
  Widget build(BuildContext context) {
    var name = notification.appName ?? appLabel;
    var title = notification.title ?? name;
    var primary = dark ? Colors.white : const Color(0xFF111111);
    var secondary = dark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0x8C3C3C43);
    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      decoration: TextDecoration.none,
      height: 1.25,
    );
    Widget tile = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF3478F6),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: name == null || name.isEmpty
          ? const Icon(Icons.notifications, size: 22, color: Colors.white)
          : Text(
              name.substring(0, 1).toUpperCase(),
              style: style(20, FontWeight.w600, Colors.white),
            ),
    );
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xF22C2C2E) : const Color(0xF2F2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The real icon has no corner baked in — the OS masks it, so this
          // does too.
          if (appIcon case var icon?)
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image(
                image: icon,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => tile,
              ),
            )
          else
            tile,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title ?? 'Notification',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(15, FontWeight.w600, primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('now', style: style(13, FontWeight.w400, secondary)),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  notification.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: style(15, FontWeight.w400, primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A document as a sheet of paper: identity on top, content below where the
/// format renders — text and images do, everything else shows what it is and
/// leaves opening to the desktop.
///
/// The anatomy is a paper sheet's, not a panel card's: a soft shadow lifting
/// it off the canvas and a folded corner — the cue that says "document" at
/// the strip's half-scale, where the words are too small to.
class _DocumentSheet extends StatelessWidget {
  const _DocumentSheet({
    required this.attachment,
    this.width = 440,
    this.height = 580,
  });

  final ScenarioRunAttachment attachment;
  final double width;
  final double height;

  /// The folded corner's side.
  static const _ear = 36.0;

  static bool _textish(String? mime) {
    if (mime == null) return false;
    return mime.startsWith('text/') ||
        mime.endsWith('/json') ||
        mime.endsWith('+json') ||
        mime.endsWith('/xml') ||
        mime.endsWith('+xml');
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var mime = attachment.mimeType;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _PaperPainter(
              fill: colors.bg,
              line: colors.line,
              fold: colors.panel2,
              ear: _ear,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Out from under the folded corner.
                  padding: const EdgeInsets.only(right: _ear),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.name,
                        style: context.type.heading,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(FwSpacing.xs),
                      Text(
                        [
                          p.basename(attachment.file),
                          ?mime,
                          scenarioAttachmentSize(attachment.bytes),
                        ].join(' · '),
                        style: context.type.caption.copyWith(
                          color: colors.mut2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Gap(FwSpacing.lg),
                const Divider(height: 1),
                const Gap(FwSpacing.lg),
                Expanded(child: _content(context, mime)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, String? mime) {
    var artifacts = ScenarioArtifactsScope.of(context);
    if (mime != null && mime.startsWith('image/')) {
      return Align(
        alignment: Alignment.topCenter,
        child: Image(
          image: artifacts.encodedImage(attachment.file),
          fit: BoxFit.contain,
        ),
      );
    }
    if (_textish(mime)) {
      return FutureBuilder<String?>(
        future: artifacts.readString(attachment.file),
        builder: (context, snapshot) {
          var text = snapshot.data;
          if (text == null) return const SizedBox.shrink();
          // A preview, not a reader: enough to say what the document is,
          // capped so a megabyte of JSON does not become a megabyte of
          // glyphs on a flow card.
          const cap = 4000;
          return Text(
            text.length > cap ? '${text.substring(0, cap)}…' : text,
            style: context.type.mono.copyWith(fontSize: 12, height: 1.5),
            overflow: TextOverflow.fade,
          );
        },
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: context.colors.mut3,
          ),
          const Gap(FwSpacing.md),
          Text(p.basename(attachment.file), style: context.type.bodyMuted),
        ],
      ),
    );
  }
}

/// The sheet itself: fill, hairline, shadow and the folded corner, one
/// painter — a border cannot follow a cut corner, so the outline is drawn
/// rather than decorated.
class _PaperPainter extends CustomPainter {
  const _PaperPainter({
    required this.fill,
    required this.line,
    required this.fold,
    required this.ear,
  });

  final Color fill;
  final Color line;
  final Color fold;
  final double ear;

  @override
  void paint(Canvas canvas, Size size) {
    var sheet = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - ear, 0)
      ..lineTo(size.width, ear)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(sheet, Colors.black.withValues(alpha: 0.4), 10, true);
    canvas.drawPath(sheet, Paint()..color = fill);
    // The flap, folded down over the front.
    var flap = Path()
      ..moveTo(size.width - ear, 0)
      ..lineTo(size.width, ear)
      ..lineTo(size.width - ear, ear)
      ..close();
    canvas.drawPath(flap, Paint()..color = fold);
    var outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;
    canvas.drawPath(sheet, outline);
    canvas.drawPath(flap, outline);
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.fill != fill || old.line != line || old.fold != fold;
}

/// The screen [attachment] arrived over: the step itself for one that
/// trailed the run, the previous screen for one that rode the capture — the
/// parent where the run recorded parents, the list's previous step where it
/// did not.
ScenarioRunStep? scenarioAttachmentBackground(
  List<ScenarioRunStep> steps,
  ScenarioRunStep step,
  ScenarioRunAttachment attachment,
) {
  if (attachment.after) return step;
  if (step.parent case var parent?) {
    for (var candidate in steps) {
      if (candidate.index == parent) return candidate;
    }
    return null;
  }
  var position = steps.indexOf(step);
  return position > 0 ? steps[position - 1] : null;
}

String scenarioAttachmentSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} kB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// One attachment, pushed over the flow the way a step is: the thing big,
/// its facts and the way out to the desktop underneath.
class ScenarioAttachmentPage extends StatelessWidget {
  const ScenarioAttachmentPage({
    super.key,
    required this.step,
    required this.index,
    required this.background,
    required this.device,
    required this.onBack,
    required this.statusFallback,
    this.appLabel,
    this.appIcon,
  });

  final ScenarioRunStep step;

  /// Which of [step]'s attachments this page is.
  final int index;

  /// The step whose screen a notification arrived over — see
  /// [ScenarioAttachmentShot.background].
  final ScenarioRunStep? background;

  final Device? device;
  final VoidCallback onBack;
  final Brightness statusFallback;
  final String? appLabel;
  final ImageProvider? appIcon;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var attachment = step.attachments[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.md,
          ),
          child: Row(
            children: [
              Tappable(
                onTap: onBack,
                child: Icon(
                  Icons.arrow_back,
                  size: FwIconSize.lg,
                  color: colors.mut,
                ),
              ),
              const Gap(FwSpacing.lg),
              Expanded(
                child: Text(
                  attachment.name,
                  style: context.type.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                [
                  p.basename(attachment.file),
                  ?attachment.mimeType,
                  scenarioAttachmentSize(attachment.bytes),
                ].join(' · '),
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
              const Gap(FwSpacing.lg),
              Tappable(
                onTap: () => unawaited(
                  launchUrl(
                    ScenarioArtifactsScope.of(context).uriOf(attachment.file),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: FwIconSize.sm,
                      color: colors.mut,
                    ),
                    const Gap(FwSpacing.xs),
                    Text('Open', style: context.type.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: colors.panel2,
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ScenarioAttachmentShot(
                attachment: attachment,
                background: background,
                device: device,
                statusFallback: statusFallback,
                appLabel: appLabel,
                appIcon: appIcon,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
