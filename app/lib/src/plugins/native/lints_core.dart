import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutterware/plugins.dart';
import 'package:package_config/package_config.dart' hide findPackageConfig;
import 'package:path/path.dart' as p;

import '../../lints/model/classification.dart';
import '../../lints/model/options_scan.dart';
import '../../lints/model/pricing.dart';
import '../../lints/model/rule_catalog.dart';
import '../../previews/package_config_locator.dart';
import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'lints_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const lintsPluginId = 'flutterware.lints';

PluginCore lintsCoreFactory(PluginHost host) => LintsCore(host);

/// Which lint rules this repo evaluated, and — the point — which it never did.
///
/// The subject is the *decision record*, not the diagnostics. `dart analyze`
/// already reports what the enabled rules find; nothing reports the rules
/// that exist for this SDK and are mentioned nowhere. This core scans every
/// `analysis_options.yaml` in the repo, resolves each `include:` chain, and
/// classifies the SDK's whole rule set against them: enabled, deliberately
/// dismissed, mentioned only in a comment, or never evaluated.
///
/// Repo-scoped rather than package-scoped: options files inherit across
/// package boundaries (a member includes the root), so the union is the only
/// view in which "mentioned nowhere" is a truthful sentence.
///
/// The rule universe comes from the SDK repository's own `rules.json`, fetched
/// once per Dart version and cached forever (see [LintCatalogStore]). Within
/// `computeAll` only the disk cache is consulted — the network is out of that
/// budget — so the first-ever look at a new SDK version happens through the
/// panel or an action.
class LintsCore extends PluginCore {
  LintsCore(super.host, {LintCatalogStore? catalogStore, LintPricer? pricer})
    : _catalogStore = catalogStore ?? LintCatalogStore(),
      _pricer = pricer ?? LintPricer();

  final LintCatalogStore _catalogStore;
  final LintPricer _pricer;

  LintOptionsScan? _scan;
  LintsClassification? _classification;
  String? _dartVersion;
  String? _error;
  Future<void>? _pending;
  var _loadedWithNetwork = false;

  LintPricing? _pricing;
  String? _pricingError;
  var _pricingRunning = false;

  String get _root => host.workspace.root;

  LintOptionsScan? get scan => _scan;
  LintsClassification? get classification => _classification;
  String? get dartVersion => _dartVersion;
  String? get error => _error;
  LintPricing? get pricing => _pricing;
  String? get pricingError => _pricingError;
  bool get isPricing => _pricingRunning;

  /// True when the persisted pricing was computed for a different unevaluated
  /// set than today's — still worth showing, worth re-running.
  bool get pricingIsStale {
    var pricing = _pricing;
    var classification = _classification;
    if (pricing == null || classification == null) return false;
    return pricing.candidatesSignature !=
        LintPricing.signatureOf(_candidates(classification));
  }

  /// Scans and classifies, unless it already has. Idempotent; the panel calls
  /// this on mount. May fetch the rule catalog over the network — a panel is a
  /// person looking, which is the consent `computeAll` does not have.
  void track() => unawaited(_load(allowNetwork: true));

  /// Drops everything cached and loads again, completing when the new state is
  /// in — the shape a refresh button wants.
  Future<void> reload() {
    _scan = null;
    _classification = null;
    _error = null;
    _pending = null;
    notifyChanged();
    return _load(allowNetwork: true);
  }

  @override
  Future<void> computeAll() => _load(allowNetwork: false);

  Future<void> _load({required bool allowNetwork}) {
    if (_classification != null && (_loadedWithNetwork || !allowNetwork)) {
      return Future.value();
    }
    var pending = _pending;
    if (pending != null && (_loadedWithNetwork || !allowNetwork)) {
      return pending;
    }
    return _pending = _doLoad(allowNetwork: allowNetwork);
  }

  Future<void> _doLoad({required bool allowNetwork}) async {
    try {
      LintPricer.recoverLeftovers(_root);

      var scanner = LintOptionsScanner(
        repoRoot: _root,
        resolvePackageUri: await _packageResolver(),
      );
      var scan = scanner.scan();

      var version = LintCatalogStore.dartVersionOf(
        host.workspace.flutterSdk.root,
      );
      LintCatalog? catalog;
      if (version != null) {
        catalog = allowNetwork
            ? await _catalogStore.fetch(version)
            : _catalogStore.cachedOnly(version);
      }

      if (isDisposed) return;
      _scan = scan;
      _dartVersion = version;
      _classification = LintsClassification.build(scan: scan, catalog: catalog);
      _loadedWithNetwork = allowNetwork;
      _error = null;
      _pricing ??= _readPersistedPricing();
    } catch (e) {
      if (isDisposed) return;
      _error = '$e';
    } finally {
      _pending = null;
      notifyChanged();
    }
  }

  Future<String? Function(Uri)?> _packageResolver() async {
    var path = findPackageConfig(_root);
    if (path == null) return null;
    try {
      var config = await loadPackageConfig(File(path));
      return (Uri uri) => config.resolve(uri)?.toFilePath();
    } catch (e) {
      return null;
    }
  }

  List<String> _candidates(LintsClassification classification) => [
    for (var rule in classification.inBucket(LintBucket.unevaluated)) rule.name,
  ];

  /// Runs one analyzer pass with every unevaluated rule enabled and records
  /// what each would cost. Slow by nature — seconds to minutes — which is why
  /// it is an action and never runs on its own.
  Future<LintsPriceResult> price() async {
    await _load(allowNetwork: true);
    var classification = _classification;
    if (classification == null) {
      throw StateError(_error ?? 'The scan has not run.');
    }
    if (!classification.hasCatalog) {
      throw StateError(
        'No rule catalog for Dart $_dartVersion — the first fetch needs the '
        'network. Nothing to price without a universe to compare to.',
      );
    }
    if (_pricingRunning) {
      throw StateError('A pricing run is already in progress.');
    }

    var candidates = _candidates(classification);
    _pricingRunning = true;
    _pricingError = null;
    notifyChanged();
    try {
      var pricing = await _pricer.price(
        repoRoot: _root,
        dartExecutable: host.workspace.flutterSdk.dart,
        candidates: candidates,
      );
      if (!isDisposed) {
        _pricing = pricing;
        _persistPricing(pricing);
      }
      return LintsPriceResult(
        candidates: candidates.length,
        freeWins: pricing.freeWins,
        elapsedMs: pricing.elapsed.inMilliseconds,
        counts: pricing.counts,
      );
    } catch (e) {
      if (!isDisposed) _pricingError = '$e';
      rethrow;
    } finally {
      if (!isDisposed) {
        _pricingRunning = false;
        notifyChanged();
      }
    }
  }

  File get _pricingFile {
    var key = sha1.convert(utf8.encode(p.canonicalize(_root))).toString();
    return File(p.join(flutterwareDir(), key, 'lints-pricing.json'));
  }

  LintPricing? _readPersistedPricing() {
    try {
      var file = _pricingFile;
      if (!file.existsSync()) return null;
      return LintPricing.fromJson(
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
      );
    } catch (e) {
      return null;
    }
  }

  void _persistPricing(LintPricing pricing) {
    try {
      var file = _pricingFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(pricing.toJson()));
    } catch (e) {
      // A price that does not survive a restart only costs a re-run.
    }
  }

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async => switch (actionId) {
    'status' => _status(),
    'price' => price(),
    _ => super.invoke(actionId, arguments: arguments),
  };

  Future<LintsStatusResult> _status() async {
    await _load(allowNetwork: true);
    var scan = _scan;
    var classification = _classification;
    if (scan == null || classification == null) {
      throw StateError(_error ?? 'The scan has not run.');
    }
    var pricing = _pricing;
    return LintsStatusResult(
      dartVersion: _dartVersion,
      catalogAvailable: classification.hasCatalog,
      universe: classification.universe,
      files: [
        for (var file in scan.files)
          LintsFileSummary(
            path: file.path,
            includeChain: file.includeChain,
            inheritsNothing: !file.hasInclude,
            includeErrors: file.includeErrors,
            configured: file.mentions.length,
            enabled: file.enabled.length,
          ),
      ],
      rules: [
        for (var rule in classification.rules.sorted(compareBySinceDesc))
          LintsRuleEntry(
            name: rule.name,
            bucket: rule.bucket.name,
            since: rule.rule?.sinceDartSdk,
            state: rule.rule?.state,
            fix: rule.rule?.fixStatus,
            description: rule.rule?.description,
            enabledVia: rule.enabledVia,
            comment: rule.comment,
            files: rule.files,
            incompatible: rule.rule?.incompatible ?? const [],
            price: rule.bucket == LintBucket.unevaluated
                ? pricing?.counts[rule.name]
                : null,
          ),
      ],
      unknownNames: classification.unknownNames,
      pricing: pricing == null
          ? null
          : LintsPricingSummary(
              at: pricing.at.toIso8601String(),
              elapsedMs: pricing.elapsed.inMilliseconds,
              freeWins: pricing.freeWins,
              stale: pricingIsStale,
            ),
    );
  }

  @override
  PluginReport get report {
    var classification = _classification;
    return PluginReport(
      id: host.id,
      label: host.label,
      status: _statusLine(classification),
      badge: switch (classification?.count(LintBucket.unevaluated)) {
        null || 0 => StatusBadge.none,
        var count => StatusBadge.count(count),
      },
      actions: [
        PluginAction(
          'status',
          'Status',
          returns: LintsStatusResult,
          description:
              'Every rule the SDK offers this project, classified against '
              'every analysis_options.yaml in the repo: enabled, dismissed, '
              'mentioned in a comment, or never evaluated',
        ),
        PluginAction(
          'price',
          'Price rules',
          returns: LintsPriceResult,
          description:
              'One dart analyze run with every unevaluated rule enabled — '
              'reports how many diagnostics each would add today. Costs a '
              'full analysis of the repo (seconds to minutes)',
        ),
      ],
      view: _view(classification),
    );
  }

  String? _itemDetail(ClassifiedLint rule, LintPricing? pricing) {
    var parts = [
      if (rule.rule?.sinceDartSdk case var since?) 'since $since',
      if (pricing?.counts[rule.name] case var price?)
        price == 0 ? 'free' : '$price issues',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Status _statusLine(LintsClassification? classification) {
    if (_pricingRunning) return const Status.info('pricing…');
    if (_error != null) return Status.error(_error!);
    if (classification == null) {
      return _pending != null ? const Status.info('scanning…') : Status.none;
    }
    if (!classification.hasCatalog) {
      return const Status.warn('no rule catalog — first fetch needs network');
    }
    var unevaluated = classification.count(LintBucket.unevaluated);
    if (unevaluated == 0) return const Status.good('every rule evaluated');
    return Status.info(
      '$unevaluated unevaluated · ${classification.count(LintBucket.enabled)} on',
    );
  }

  PluginView _view(LintsClassification? classification) {
    if (classification == null) return PluginView.empty;
    var scan = _scan;
    var pricing = _pricing;
    var newest = classification
        .inBucket(LintBucket.unevaluated)
        .sorted(compareBySinceDesc)
        .take(12)
        .toList();
    return PluginView([
      ViewField('Dart', _dartVersion ?? 'unknown'),
      ViewField('Enabled', '${classification.count(LintBucket.enabled)}'),
      ViewField('Dismissed', '${classification.count(LintBucket.dismissed)}'),
      ViewField('Mentioned', '${classification.count(LintBucket.mentioned)}'),
      ViewField(
        'Unevaluated',
        '${classification.count(LintBucket.unevaluated)}',
        tone: classification.count(LintBucket.unevaluated) > 0
            ? Tone.info
            : Tone.good,
      ),
      if (scan != null) ViewField('Options files', '${scan.files.length}'),
      if (pricing != null)
        ViewField(
          'Priced',
          '${pricing.freeWins} free wins'
              '${pricingIsStale ? ' (stale — set changed)' : ''}',
        ),
      if (classification.unknownNames.isNotEmpty)
        ViewField(
          'Unknown rules',
          classification.unknownNames.join(', '),
          tone: Tone.warn,
        ),
      if (newest.isNotEmpty)
        ViewItems([
          for (var rule in newest)
            ViewItem(rule.name, detail: _itemDetail(rule, pricing)),
        ]),
    ]);
  }
}
