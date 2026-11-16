final RegExp _forbiddenVideoUrlChars = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060-\u2069\uFEFF\\]',
);
final RegExp _encodedVideoBidi = RegExp(
  r'%(?:c2%[89][0-9a-f]|e2%80%(?:8[b-f]|a[8-e])|e2%81%a[0-9]|d8%9c|ef%bb%bf)',
  caseSensitive: false,
);
final RegExp _fullWidthVideoDots = RegExp(r'[\u3002\uFF0E\uFF61]');
final RegExp _windowsReservedVideoStem = RegExp(
  r'^(?:con|prn|aux|nul|conin\$|conout\$|clock\$|com[1-9]|lpt[1-9])(?:\..*)?$',
  caseSensitive: false,
);

List<int>? _tryParseVideoIpv4Octets(String host) {
  if (host.isEmpty || host.contains(':')) return null;
  final parts = host.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final parsed = <int>[];
  for (final part in parts) {
    if (part.isEmpty) return null;
    int? val;
    if (part.startsWith('0x') || part.startsWith('0X')) {
      if (part.length <= 2 || part.length > 10) return null;
      val = int.tryParse(part.substring(2), radix: 16);
    } else if (part.length > 1 && part.startsWith('0')) {
      if (!RegExp(r'^[0-7]+$').hasMatch(part)) return null;
      val = int.tryParse(part, radix: 8);
    } else if (RegExp(r'^\d+$').hasMatch(part)) {
      if (part.length > 10) return null;
      val = int.tryParse(part, radix: 10);
    } else {
      return null;
    }
    if (val == null || val < 0) return null;
    parsed.add(val);
  }
  int ipv4Int;
  if (parsed.length == 1) {
    if (parsed[0] > 0xFFFFFFFF) return null;
    ipv4Int = parsed[0];
  } else if (parsed.length == 2) {
    if (parsed[0] > 0xFF || parsed[1] > 0xFFFFFF) return null;
    ipv4Int = parsed[0] * 0x1000000 + parsed[1];
  } else if (parsed.length == 3) {
    if (parsed[0] > 0xFF || parsed[1] > 0xFF || parsed[2] > 0xFFFF) {
      return null;
    }
    ipv4Int = parsed[0] * 0x1000000 + parsed[1] * 0x10000 + parsed[2];
  } else {
    if (parsed.any((v) => v > 0xFF)) return null;
    ipv4Int =
        parsed[0] * 0x1000000 +
        parsed[1] * 0x10000 +
        parsed[2] * 0x100 +
        parsed[3];
  }
  return <int>[
    (ipv4Int ~/ 0x1000000) & 0xFF,
    (ipv4Int ~/ 0x10000) & 0xFF,
    (ipv4Int ~/ 0x100) & 0xFF,
    ipv4Int & 0xFF,
  ];
}

/// Pure-Dart local filesystem path guard for video project/export inputs.
bool isProtectedLocalVideoPath(String rawPath) {
  if (_forbiddenVideoUrlChars.hasMatch(rawPath) ||
      _encodedVideoBidi.hasMatch(rawPath)) {
    return true;
  }
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('-') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith(r'\\') ||
      trimmed.startsWith(r'\??\')) {
    return true;
  }
  final norm = trimmed.replaceAll('\\', '/');
  final lower = norm.toLowerCase();
  if (lower.contains('%00') ||
      lower.contains('%2e') ||
      lower.contains('%2f') ||
      lower.contains('%5c') ||
      lower.contains('%25')) {
    return true;
  }
  final segments = norm.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.any((s) => s == '..')) return true;
  if (lower.startsWith('/etc/') ||
      lower == '/etc' ||
      lower.startsWith('/private/etc/') ||
      lower.startsWith('/proc/') ||
      lower.startsWith('/sys/') ||
      lower.startsWith('/dev/')) {
    return true;
  }
  for (var i = 0; i < segments.length; i++) {
    final rawSeg = segments[i];
    if (rawSeg.contains(':') &&
        !(i == 0 &&
            RegExp(r'^[a-zA-Z]:$').hasMatch(rawSeg) &&
            !trimmed.startsWith('/'))) {
      return true;
    }
    if (_windowsReservedVideoStem.hasMatch(rawSeg)) {
      return true;
    }
    final s = rawSeg.toLowerCase();
    if (s == '.ssh' ||
        s == '.aws' ||
        s == '.gnupg' ||
        s == '.kube' ||
        s == '.git' ||
        s == 'keychains' ||
        s == '.azure' ||
        s == '.env' ||
        s.startsWith('.env.') ||
        s == '.secret.local' ||
        s == '.netrc' ||
        s == '.git-credentials' ||
        s == '.npmrc' ||
        s == '.pypirc' ||
        s == '.pgpass' ||
        s == '.vault-token' ||
        s == 'terraform.tfstate' ||
        s == 'id_rsa' ||
        s == 'id_ed25519' ||
        s == 'authorized_keys') {
      return true;
    }
    if (s == '.config' &&
        i + 1 < segments.length &&
        segments[i + 1].toLowerCase() == 'gcloud') {
      return true;
    }
  }
  return false;
}

/// Pure-Dart SSRF guard for raw video export URL strings (inspected before
/// `Uri.tryParse` normalizes `%2e` dot-segments).
bool isSafePublicVideoExportUrl(String rawUrl) {
  if (_forbiddenVideoUrlChars.hasMatch(rawUrl) ||
      _encodedVideoBidi.hasMatch(rawUrl)) {
    return false;
  }
  final trimmed = rawUrl.trim();
  final lower = trimmed.toLowerCase();
  if (trimmed.isEmpty ||
      trimmed.length > 2048 ||
      lower.contains('%00') ||
      lower.contains('%5c') ||
      lower.contains('%2f') ||
      lower.contains('%2e') ||
      lower.contains('%25') ||
      lower.contains('/..')) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  return isSafePublicVideoExportUri(uri);
}

/// Pure-Dart SSRF guard for video export remote HTTP(S) inputs.
///
/// Shared between native and web stub exporters so security validation behaves
/// identically across Dart VM, Dart2JS, and Dart2Wasm.
bool isSafePublicVideoExportUri(Uri uri) {
  final raw = uri.toString();
  final lowerRaw = raw.toLowerCase();
  if (_forbiddenVideoUrlChars.hasMatch(raw) ||
      _encodedVideoBidi.hasMatch(lowerRaw) ||
      lowerRaw.contains('%00') ||
      lowerRaw.contains('%5c') ||
      lowerRaw.contains('%2f') ||
      lowerRaw.contains('%2e') ||
      lowerRaw.contains('%25') ||
      lowerRaw.contains('/..')) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return false;
  if (!uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.pathSegments.any((seg) => seg == '..')) {
    return false;
  }
  final schemeSep = raw.indexOf('://');
  if (schemeSep <= 0) return false;
  final rest = raw.substring(schemeSep + 3);
  var authEnd = rest.length;
  for (final sep in const <String>['/', '?', '#']) {
    final idx = rest.indexOf(sep);
    if (idx >= 0 && idx < authEnd) authEnd = idx;
  }
  final rawAuthority = rest.substring(0, authEnd);
  if (rawAuthority.isEmpty ||
      rawAuthority.contains('@') ||
      rawAuthority.contains('%') ||
      _fullWidthVideoDots.hasMatch(rawAuthority)) {
    return false;
  }
  var host = uri.host.trim().toLowerCase();
  if (host.isEmpty) return false;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  if (host.isEmpty ||
      host.contains('%') ||
      host == 'null' ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.corp') ||
      host.endsWith('.lan') ||
      host.endsWith('.home.arpa') ||
      host.endsWith('.invalid') ||
      host.endsWith('.test') ||
      host.endsWith('.example') ||
      host.endsWith('.ts.net') ||
      host.endsWith('.onion') ||
      host == 'metadata' ||
      host == 'instance-data' ||
      host == 'metadata.goog' ||
      host.endsWith('.metadata.goog') ||
      host == 'metadata.google.internal' ||
      host.endsWith('.metadata.google.internal') ||
      host == 'metadata.azure.com' ||
      host.endsWith('.metadata.azure.com') ||
      host == 'metadata.azure.internal' ||
      host.endsWith('.metadata.azure.internal') ||
      (!host.contains(':') && !host.contains('.'))) {
    return false;
  }
  if (host.contains(':')) {
    return _isSafePublicIpv6(host);
  }
  final octets = _tryParseVideoIpv4Octets(host);
  if (octets != null) {
    if (!RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
            .hasMatch(host) ||
        host.split('.').any((p) => p.length > 1 && p.startsWith('0'))) {
      return false;
    }
    return _isPublicIpv4Octets(octets[0], octets[1], octets[2], octets[3]);
  }
  return true;
}

bool _isPublicIpv4Octets(int a, int b, int c, int d) {
  if (a == 0 || a == 10 || a == 127) return false;
  if (a == 169 && b == 254) return false;
  if (a == 172 && b >= 16 && b <= 31) return false;
  if (a == 192 && b == 168) return false;
  if (a == 100 && b >= 64 && b <= 127) return false;
  if (a == 198 && (b == 18 || b == 19)) return false;
  if (a == 192 && b == 0 && (c == 0 || c == 2)) return false;
  if (a == 198 && b == 51 && c == 100) return false;
  if (a == 203 && b == 0 && c == 113) return false;
  if (a >= 224) return false;
  if (a == 255 && b == 255 && c == 255 && d == 255) return false;
  return true;
}

bool _isSafePublicIpv6(String raw) {
  if (raw.contains('%')) return false;
  final addr = raw.toLowerCase();
  if (addr.isEmpty ||
      addr == '::' ||
      addr == '::1' ||
      RegExp(r'^(?:0+:){6,7}0*[01]$').hasMatch(addr)) {
    return false;
  }
  if (addr.startsWith('fc') ||
      addr.startsWith('fd') ||
      addr.startsWith('fe8') ||
      addr.startsWith('fe9') ||
      addr.startsWith('fea') ||
      addr.startsWith('feb') ||
      addr.startsWith('ff') ||
      addr.startsWith('0:0:0:0:0:ffff:') ||
      addr.startsWith('64:ff9b:') ||
      addr.startsWith('2002:') ||
      addr.startsWith('2001:0:') ||
      addr.startsWith('2001:0000:') ||
      addr.startsWith('2001:db8:')) {
    return false;
  }
  if (addr.startsWith('::ffff:')) {
    final tail = addr.substring('::ffff:'.length);
    if (tail.contains('.')) {
      final parts = tail.split('.');
      if (parts.length != 4) return false;
      final o = parts.map(int.tryParse).toList();
      if (o.any((v) => v == null || v < 0 || v > 255)) return false;
      return _isPublicIpv4Octets(o[0]!, o[1]!, o[2]!, o[3]!);
    }
    final hexParts = tail.split(':');
    if (hexParts.length == 2) {
      final hi = int.tryParse(hexParts[0], radix: 16);
      final lo = int.tryParse(hexParts[1], radix: 16);
      if (hi == null || lo == null || hi > 0xffff || lo > 0xffff) {
        return false;
      }
      return _isPublicIpv4Octets(
        (hi >> 8) & 0xff,
        hi & 0xff,
        (lo >> 8) & 0xff,
        lo & 0xff,
      );
    }
    return false;
  }
  return true;
}
