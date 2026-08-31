/// Render a widget's painted output as a real vector document.
///
/// [captureSvg] and [capturePdf] replay a laid-out [RenderObject]'s paint
/// pass — no engine change, no compositing — into SVG or a single-page PDF.
/// Text stays text (or becomes glyph outlines read from the font file, per
/// [CaptureOptions.text]); what no vector format can express follows
/// [CaptureOptions.unsupported]: a raster patch, a flat stand-in, or
/// nothing. The result's warnings list everything the output does not carry
/// exactly as the engine would have drawn it.
///
/// Design: docs/superpowers/specs/2026-08-31-widget-export-design.md.
library;

export 'src/render/model.dart'
    show
        CaptureOptions,
        PdfResult,
        RenderFont,
        RenderWarning,
        RenderWarningKind,
        SvgResult,
        TextCluster,
        TextPolicy,
        TextRun,
        UnsupportedPolicy;
export 'src/render/render_capture.dart' show capturePdf, captureSvg;
