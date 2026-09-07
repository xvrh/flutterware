# Three targets: what broke

Step one of the scene plan is to build one of each thing a scene is for,
with what exists today, and let what breaks write the specification for what
comes next. This is that list. Nothing here was designed; every entry is
something that stopped an attempt, with the picture that shows it.

The three targets live in `examples/example/demo/`:

- `store_banner.scene.dart` — a store banner whose copy is a typed hole,
  exported once per language.
- `onboarding.scene.dart` — a screen that runs inside the app on whatever
  phone it is given.
- `invoice.scene.dart` — a document template exported as a PDF.

All three parse, render, and look like the thing they are meant to be. The
model is closer than expected. What follows is what it cannot say.

## The root has one shape, and the three targets need three

The banner is fixed on both axes and that is correct. The onboarding screen
authored at 390 wide, rendered on a 320 phone, is **clipped**: the body text
runs off the right edge and the button with it. It is not adapted, because a
scene renders at its authored size and the viewport crops it.

The invoice wants the third shape: fixed width, height that grows with the
content.

So the root is not one thing. It takes constraints, and the three products
differ only in which constraints they hand it: both axes fixed, the device's
own, or fixed width with unbounded height. Everything else in this document
is downstream of that.

## A repeater is missing, and it is not an element type

*(Built 2026-09-03. A parameter may be a list, a node may `repeat:` one, and
a property inside it reads a field as `lines.item`. The node stays one node —
one field, one tree row, one thing to select — and the copies are made where
the picture is.)*

The invoice has four line items because four is what could be typed. A real
one has as many as the data has. The authored row would be one row bound to a
list, drawn once per item, its cells bound to the item's fields.

This is the same mechanism as "mockup elements replaced at runtime", seen
from the other side, and it is why parameters and repetition have to be
designed together: a repeater is a parameter whose value is a list. Shipping
scalar binding first and adding lists later means rebuilding the binding.

## Stacked rows are not a table

*(Built 2026-09-03. `NodeLayout.table`: the column tracks belong to the
frame, so every row is measured against the same ones. A track is a size in
the same three words a node's is — hug, a number, fill.)*

In the invoice picture the quantity column does not line up. Each row is an
independent row with its own gap, so every column is as wide as that row's
text. Column widths that agree across rows are exactly what independent rows
cannot give you, and it is the thing a table widget exists for.

## Nothing after a growing block can be placed

The invoice totals sit at a fixed y because there is nothing else to say. Add
a fifth line item and the table grows into them. The same applies to the
banner: the copy column is anchored at a fixed y, so German — which wraps to
two lines — grows downward rather than staying balanced, and a longer string
would leave the artboard.

Free positioning and content that changes length are incompatible, and both
the banner and the invoice need both.

## A scene's own parameters are invisible in the editor

The banner's whole purpose is being filled per language, and the editor
offers no way to see it filled. Parameters are editable only on a **nested**
scene node, where the inspector shows the child's arguments. The scene you
are editing has parameters that nothing surfaces: you cannot read them, set
them, or preview what German does to the layout.

The three language pictures in this round were produced by a script, not by
the studio. That is the authoring loop the banner product needs and does not
have.

## There is no export loop, only its parts

Rendering the banner per language works and took a dozen lines: parse the
file, `instantiateScene` with the values, write the JSON pair, and screenshot
the `scenePlayer` preview entry with a `pair` knob. Every piece exists. What
does not exist is anything in the product that strings them together, so a
consumer would write that script themselves.

For the invoice the missing piece is larger: `capturePdf` is single page by
construction, so pagination, with a header and footer that repeat, is real
work on the render side.

## Small things that cost time

- A parameter default must be a **single** string literal. Adjacent-string
  concatenation is refused, so a sentence of body copy has to sit on one long
  line that the formatter will not wrap.
- The scene listing sat on "Looking for scenes" forever whenever the scan had
  not been started or had been invalidated, because the surface that reads the
  listing never asked for it. Fixed in this round: the panel tracks the package
  it renders, from build.
- Invalidating the listing cache does not re-read it. `rescan` only forgets;
  something has to ask again. Fixed by giving the core a `reload`.

## What this says about the order

Nothing here changes the plan, and two things sharpen it.

Auto-layout is not one improvement among several. It is the single blocker
shared by all three targets, and the root's three shapes have to be designed
as one thing rather than retrofitted for the third.

The parameter and output path is the other half, and it has to be designed
with lists in scope from the start, because the invoice needs repetition and
the banner needs substitution and they are the same mechanism.

## What the two of them did not answer

The invoice now has one authored row and columns that agree, and the two
things it still cannot do are the two the design already named:

- **Nothing after a growing block can be placed.** The totals still sit at a
  fixed y. Four items or forty, the table grows into them.
- **`capturePdf` is one page.** A list long enough to need a second page has
  nowhere to put it, header and footer included.

And one the round found: a row under a table contributes its fill, its
border and its corner, and nothing else — no padding, no size, no layout of
its own. The inspector says so rather than showing controls that do nothing,
but it is a narrowing of the uniform node the model is built on, and the
first place that bet has cost something.
