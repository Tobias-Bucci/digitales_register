import 'package:dr/diagnostics_service.dart';
import 'package:flutter/foundation.dart';

/// Local logs accept the same closed breadcrumb vocabulary as diagnostics.
/// Exception objects and payloads are never rendered, including debug builds.
void privacyLog(String category) {
  // Legacy call sites supply no diagnostic detail. Repeating this placeholder
  // obscures the specific, sanitized diagnostics emitted by feature loaders.
  if (category == 'technical_operation') return;
  if (kDebugMode) {
    debugPrint('[Register] ${DiagnosticSanitizer.log(category)}');
  }
}
