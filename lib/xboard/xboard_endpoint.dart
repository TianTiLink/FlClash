import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/utils.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart' show ttActiveBase;

const String _kApiDomainsCache = 'tt_api_domains';
const String _kActiveBaseCache = 'tt_active_base';
const String _kOfficialDomainsCache = 'tt_official_domains';
const String _kEmergencyApiBase = 'https://186.244.223.118';
const String _kBootstrapUrl = '$_kEmergencyApiBase/api/v1/reseller/bootstrap';
const String _kBootstrapBrand = 'tianti';
const String _kBootstrapPublicKey =
    'xuExWLhJahYP7i2GXhjdzFsvYmc9Sx4KSO9NWzwpMBY=';

const List<String> _kSeedApiHosts = <String>['https://pafslnnalksdf.xyz'];

class TtEndpointResult {
  final String activeBase;
  final bool online;
  final Map<String, dynamic> config;
  final String currentVersion;

  TtEndpointResult(
    this.activeBase,
    this.online,
    this.config, {
    required this.currentVersion,
  });

  String get _platformKey => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : 'pwa';

  String? get latestVersion {
    final versions = config['versions'];
    if (versions is! Map) return null;
    final value = versions[_platformKey];
    return value?.toString();
  }

  String? get downloadUrl {
    final downloads = config['downloads'];
    if (downloads is! Map) return null;
    final key = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : 'ios';
    final value = downloads[key];
    if (value == null) return null;
    final path = value.toString();
    if (path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return activeBase.replaceAll(RegExp(r'/+$'), '') + path;
  }

  bool get updateForce => config['update_force'] == true;
  String get updateNote => (config['update_note'] ?? '').toString();

  bool get hasUpdate {
    final version = latestVersion;
    return version != null && isRemoteVersionNewer(version, currentVersion);
  }
}

bool isRemoteVersionNewer(String remoteVersion, String currentVersion) {
  String normalize(String version) {
    return version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  final remote = normalize(remoteVersion);
  final current = normalize(currentVersion);
  if (remote.isEmpty || current.isEmpty) return false;
  try {
    return utils.compareVersions(remote, current) > 0;
  } catch (_) {
    return false;
  }
}

String buildBootstrapPayload({
  required String brand,
  required int issuedAt,
  required int expiresAt,
  required List<String> apiDomains,
}) {
  return <String>[
    'v1',
    brand,
    issuedAt.toString(),
    expiresAt.toString(),
    ...apiDomains,
  ].join('\n');
}

Future<List<String>> verifyBootstrapDocument(
  Map<String, dynamic> document, {
  required String expectedBrand,
  required String publicKeyBase64,
  DateTime? now,
}) async {
  try {
    final wrapped = document['data'];
    final data = wrapped is Map ? Map<String, dynamic>.from(wrapped) : document;
    final version = data['version'];
    final brand = data['brand'];
    final issuedAt = data['issued_at'];
    final expiresAt = data['expires_at'];
    final rawDomains = data['api_domains'];
    final encodedSignature = data['signature'];
    if (version != 1 ||
        brand != expectedBrand ||
        issuedAt is! int ||
        expiresAt is! int ||
        rawDomains is! List ||
        encodedSignature is! String) {
      return const <String>[];
    }

    final nowSeconds =
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    final lifetime = expiresAt - issuedAt;
    if (issuedAt > nowSeconds + 600 ||
        expiresAt < nowSeconds - 300 ||
        lifetime <= 0 ||
        lifetime > const Duration(days: 2).inSeconds) {
      return const <String>[];
    }

    final domains = <String>[];
    for (final value in rawDomains.take(8)) {
      final normalized = _validatedApiBase(value.toString());
      if (normalized == null) return const <String>[];
      if (!domains.contains(normalized)) domains.add(normalized);
    }
    if (domains.isEmpty) return const <String>[];

    final publicKeyBytes = base64Decode(publicKeyBase64);
    final signatureBytes = base64Decode(encodedSignature);
    if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
      return const <String>[];
    }
    final payload = buildBootstrapPayload(
      brand: brand,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      apiDomains: domains,
    );
    final signature = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
    final valid = await Ed25519().verify(
      utf8.encode(payload),
      signature: signature,
    );
    return valid ? domains : const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

String? _validatedApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (InternetAddress.tryParse(host) != null ||
      !host.contains('.') ||
      !RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
      host.contains('..')) {
    return null;
  }
  return 'https://$host';
}

void _addHost(List<String> list, String? host) {
  if (host == null) return;
  var value = host.trim();
  if (value.isEmpty) return;
  if (!value.startsWith('http')) value = 'https://$value';
  final validated = _validatedApiBase(value);
  // An IP saved during a previous emergency session must not become a normal
  // first-choice candidate. Every cold start retries the domains before IP.
  if (validated != null && !list.contains(validated)) list.add(validated);
}

Future<List<String>> _candidates() async {
  final list = <String>[];
  try {
    final preferences = await SharedPreferences.getInstance();
    _addHost(list, preferences.getString(_kActiveBaseCache));
    final cached = preferences.getStringList(_kApiDomainsCache);
    if (cached != null) {
      for (final host in cached) {
        _addHost(list, host);
      }
    }
  } catch (_) {}
  _addHost(list, ttActiveBase);
  for (final host in _kSeedApiHosts) {
    _addHost(list, host);
  }
  return list;
}

Future<Map<String, dynamic>> _probe(String base, Duration timeout) async {
  final uri = Uri.parse('$base/api/v1/reseller/appconfig');
  final response = await http
      .get(uri, headers: {'Accept': 'application/json'})
      .timeout(timeout);
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }
  final json = jsonDecode(response.body);
  if (json is Map && json['data'] is Map) {
    return Map<String, dynamic>.from(json['data'] as Map);
  }
  throw Exception('bad body');
}

Future<List<String>> _fetchBootstrapDomains(Duration timeout) async {
  try {
    final response = await http
        .get(Uri.parse(_kBootstrapUrl), headers: {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200 || response.bodyBytes.length > 16384) {
      return const <String>[];
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) return const <String>[];
    return verifyBootstrapDocument(
      Map<String, dynamic>.from(json),
      expectedBrand: _kBootstrapBrand,
      publicKeyBase64: _kBootstrapPublicKey,
    );
  } catch (_) {
    return const <String>[];
  }
}

Future<void> _cacheApiDomains(List<String> domains) async {
  if (domains.isEmpty) return;
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_kApiDomainsCache, domains);
  } catch (_) {}
}

Future<TtEndpointResult> _activate(
  String base,
  Map<String, dynamic> config,
  String currentVersion,
) async {
  ttActiveBase = base;
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_kActiveBaseCache, base);
    final apiDomains = config['api_domains'];
    if (apiDomains is List && apiDomains.isNotEmpty) {
      await preferences.setStringList(
        _kApiDomainsCache,
        apiDomains.map((value) => value.toString()).toList(),
      );
    }
    final officialDomains = config['official_domains'];
    if (officialDomains is List && officialDomains.isNotEmpty) {
      await preferences.setStringList(
        _kOfficialDomainsCache,
        officialDomains.map((value) => value.toString()).toList(),
      );
    }
  } catch (_) {}
  return TtEndpointResult(base, true, config, currentVersion: currentVersion);
}

Future<TtEndpointResult> resolveEndpoint({
  required String currentVersion,
  Duration perTry = const Duration(seconds: 6),
}) async {
  final candidates = await _candidates();
  for (final base in candidates) {
    try {
      final config = await _probe(base, perTry);
      return _activate(base, config, currentVersion);
    } catch (_) {}
  }

  final discovered = await _fetchBootstrapDomains(perTry);
  await _cacheApiDomains(discovered);
  for (final base in discovered) {
    if (candidates.contains(base)) continue;
    try {
      final config = await _probe(base, perTry);
      return _activate(base, config, currentVersion);
    } catch (_) {}
  }

  // Last resort: the fixed IP has a trusted IP-address TLS certificate. It is
  // attempted only after cached, built-in and freshly discovered domains fail.
  try {
    final config = await _probe(_kEmergencyApiBase, perTry);
    return _activate(_kEmergencyApiBase, config, currentVersion);
  } catch (_) {}

  return TtEndpointResult(
    ttActiveBase,
    false,
    const <String, dynamic>{},
    currentVersion: currentVersion,
  );
}

Future<String> officialSiteBase() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final list = preferences.getStringList(_kOfficialDomainsCache);
    if (list != null && list.isNotEmpty) {
      var host = list.first.trim();
      if (host.isNotEmpty) {
        if (!host.startsWith('http')) host = 'https://$host';
        return host.replaceAll(RegExp(r'/+$'), '');
      }
    }
  } catch (_) {}
  return 'https://tiantiweb.xyz';
}
