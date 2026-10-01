import 'package:dr/diagnostics_service.dart';
import 'package:flutter/foundation.dart';

/// Local logs accept the same closed breadcrumb vocabulary as diagnostics.
/// Exception objects and payloads are never rendered, including debug builds.
void privacyLog(String category) {
  if (kDebugMode) {
    debugPrint(
        '[Register] ${category == 'technical_operation' ? category : DiagnosticSanitizer.log(category)}');
  }
}
