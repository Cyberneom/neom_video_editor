import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('Origin')
extension type _JsOrigin._(JSObject _) implements JSObject {
  external static _JsOrigin from(JSAny? value);
  external bool get opaque;
  external bool isSameOrigin(_JsOrigin other);
}

@JS('URL')
extension type _JsUrl._(JSObject _) implements JSObject {
  external factory _JsUrl(String url);
  external String get origin;
}

@JS('trustedTypes')
external JSObject? get _trustedTypes;

JSObject? _exportScriptPolicy;
bool _exportScriptPolicyAttempted = false;
final RegExp _forbiddenWebUrlChars = RegExp(
  r'[\x00-\x20\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060\u2066-\u2069\uFEFF\u3002\uFF0E\uFF61\\]',
);

bool _hasGlobalOriginApi() => globalContext.has('Origin');

/// Validates that [candidateUrl] shares the exact tuple origin of `globalThis`
/// using the HTML `Origin` API (`Origin.from(globalThis)`) when supported,
/// falling back to `new URL()` tuple-origin comparison while rejecting `"null"`
/// opaque origins.
bool isSameOriginWebUrl(String candidateUrl) {
  final trimmed = candidateUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 4096 ||
      trimmed.toLowerCase() == 'null' ||
      _forbiddenWebUrlChars.hasMatch(trimmed)) {
    return false;
  }
  try {
    if (_hasGlobalOriginApi()) {
      final candidate = _JsOrigin.from(trimmed.toJS);
      final current = _JsOrigin.from(globalContext);
      if (candidate.opaque || current.opaque) return false;
      return candidate.isSameOrigin(current);
    }
  } catch (_) {
    return false;
  }
  try {
    final currentHref = web.window.location.href;
    if (currentHref.isEmpty) return false;
    final candidate = _JsUrl(trimmed);
    final current = _JsUrl(currentHref);
    return candidate.origin != 'null' &&
        current.origin != 'null' &&
        candidate.origin == current.origin;
  } catch (_) {
    return false;
  }
}

/// Validates that a `blob:` [uri] was minted by the current document's tuple
/// origin (e.g. `blob:https://app.example.com/<uuid>`) and is not an opaque
/// `blob:null/...` or cross-origin `blob:` reference.
bool isSameOriginBlobUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'blob') return false;
  final raw = uri.toString().trim();
  if (!raw.toLowerCase().startsWith('blob:') || raw.length <= 5) return false;
  final inner = raw.substring(5).trim();
  if (inner.isEmpty || inner.toLowerCase().startsWith('null')) return false;
  return isSameOriginWebUrl(inner);
}

/// Assigns `script.src` via a Trusted Types `ScriptURL` policy when Trusted
/// Types is available on `window`, verifying same-origin asset resolution first.
void assignVerifiedExportScriptSrc(
  web.HTMLScriptElement script,
  String assetUrl,
) {
  final resolved = Uri.base.resolve(assetUrl).toString();
  if (!isSameOriginWebUrl(resolved) ||
      !resolved.endsWith(
        'packages/neom_video_editor/assets/web/neom_video_export.bundle.js',
      )) {
    throw StateError('URL de script del exportador web bloqueada por origen.');
  }

  final tt = _trustedTypes;
  if (tt != null && !_exportScriptPolicyAttempted) {
    _exportScriptPolicyAttempted = true;
    try {
      final rules = JSObject();
      rules.setProperty(
        'createScriptURL'.toJS,
        ((JSString input) {
          final value = input.toDart;
          if (!isSameOriginWebUrl(value) ||
              !value.endsWith(
                'packages/neom_video_editor/assets/web/neom_video_export.bundle.js',
              )) {
            throw StateError('Rejected untrusted exporter ScriptURL');
          }
          return value.toJS;
        }).toJS,
      );
      _exportScriptPolicy =
          tt.callMethodVarArgs<JSObject>('createPolicy'.toJS, [
            'neom-video-export'.toJS,
            rules,
          ]);
    } catch (_) {
      _exportScriptPolicy = null;
    }
  }

  final policy = _exportScriptPolicy;
  if (policy != null) {
    final trustedUrl = policy.callMethodVarArgs<JSAny>(
      'createScriptURL'.toJS,
      [resolved.toJS],
    );
    (script as JSObject).setProperty('src'.toJS, trustedUrl);
    return;
  }
  script.src = resolved;
}
