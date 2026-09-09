// The bridge between a font's axes and the scene's key space.
//
// The property table cannot list an axis: `wght` and `wdth` are declared by
// whatever face a text is set in, and the studio only learns them by opening
// the file. So the panels that offer keys — the inspector's sliders, the
// timeline's tracks — take a lookup and ask it, and this is where the answer
// becomes something the rest of the editor already understands.
import 'package:flutterware/scene_authoring.dart';

import '../assets/model/font_axes.dart';

/// What a family's axes are, in the package the scene belongs to.
typedef AxesLookup = List<FontAxis> Function(String family);

/// The axes of whatever face [t] is set in — none when it names no family,
/// the family is static, or nobody scanned.
List<FontAxis> sceneAxesOf(TextNode t, AxesLookup? axesFor) =>
    switch ((axesFor, t.fontFamily)) {
      (var lookup?, var family?) => lookup(family),
      _ => const [],
    };

/// Everything [node] can be animated on, the face's axes included.
///
/// [animatableProps] answers for the table's rows and stops there, which is
/// right: an axis is not one. Each axis arrives as an ordinary number spec
/// keyed `axes.<tag>`, with the range and the resting value the FONT gives —
/// the resting value being the one nobody could have guessed, since a face's
/// default weight is not always 400.
List<ScenePropSpec> sceneAnimatableProps(SceneNode node, AxesLookup? axesFor) =>
    [
      ...animatableProps(node),
      if (node is TextNode)
        for (var axis in sceneAxesOf(node, axesFor))
          ScenePropSpec(
            '$sceneAxesPrefix${axis.tag}',
            TrackKind.number,
            identity: axis.def,
            softMin: axis.min,
            softMax: axis.max,
          ),
    ];

/// What a key is called where there is room for a word — `axes.wght` is
/// *Weight*. Falls back to the key itself, which is what an argument and an
/// unregistered axis both want.
String sceneKeyLabel(String key) =>
    switch ((sceneAxisTag(key), sceneArgName(key))) {
      (var tag?, _) => fontAxisLabel(tag),
      (_, var arg?) => arg,
      _ => key,
    };
