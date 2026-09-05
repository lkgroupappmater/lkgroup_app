import '../core/route_catalog.dart';

class ExcelFileMetadata {
  const ExcelFileMetadata({
    required this.routeKey,
    required this.year,
    required this.voyage,
  });

  final String routeKey;
  final int year;
  final String voyage;

  String get routeLabel => RouteCatalog.labelForKey(routeKey);
}

/// Reads the route/year/voyage tokens from an Excel file name without forcing
/// one exact file name. Descriptive text may be added before or after the
/// tokens, and both regular OOXML and macro-enabled workbooks are accepted.
class ExcelFileMetadataParser {
  ExcelFileMetadataParser._();

  static const supportedExtensions = <String>['xlsx', 'xlsm'];

  static ExcelFileMetadata? tryParse(String fileName) {
    final leaf = fileName.replaceAll('\\', '/').split('/').last.trim();
    final extensionMatch = RegExp(
      r'\.([A-Za-z0-9]+)$',
    ).firstMatch(leaf);
    final extension = extensionMatch?.group(1)?.toLowerCase() ?? '';
    if (!supportedExtensions.contains(extension)) return null;

    final stem = leaf.substring(0, extensionMatch!.start);
    final routeKey = _routeKey(stem);
    final year = _year(stem);
    final voyage = _voyage(stem);
    if (routeKey == null || year == null || voyage == null) return null;

    return ExcelFileMetadata(
      routeKey: routeKey,
      year: year,
      voyage: voyage,
    );
  }

  static String? _routeKey(String value) {
    final flat = value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9가-힣]+'), '');

    final definitions = RouteCatalog.definitions.toList(growable: false)
      ..sort(
        (a, b) => b.filePrefix.length.compareTo(a.filePrefix.length),
      );
    for (final definition in definitions) {
      final fileToken = definition.filePrefix
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9가-힣]+'), '');
      final labelToken = definition.displayName
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9가-힣]+'), '');
      if ((fileToken.isNotEmpty && flat.contains(fileToken)) ||
          (labelToken.isNotEmpty && flat.contains(labelToken))) {
        return definition.routeKey;
      }
    }

    const aliases = <String, List<String>>{
      'kr_la_sea': <String>[
        'LKS',
        'KORLAOSEA',
        'KOREALAOSSEA',
        '한국라오스해상',
      ],
      'kr_la_air': <String>[
        'LKA',
        'KORLAOAIR',
        'KOREALAOSAIR',
        '한국라오스항공',
      ],
    };
    for (final entry in aliases.entries) {
      for (final alias in entry.value) {
        if (alias.length <= 3) {
          final token = RegExp(
            '(^|[^A-Z0-9])${RegExp.escape(alias)}([^A-Z0-9]|\$)',
            caseSensitive: false,
          );
          if (token.hasMatch(value)) return entry.key;
        } else if (flat.contains(alias)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  static int? _year(String value) {
    final match = RegExp(
      r'(?:^|[^0-9])((?:19|20)[0-9]{2})(?:[^0-9]|$)',
    ).firstMatch(value);
    return int.tryParse(match?.group(1) ?? '');
  }

  static String? _voyage(String value) {
    final upper = value.toUpperCase();
    final vMatch = RegExp(
      r'(?:^|[^A-Z0-9])V(?:OYAGE)?[\s_-]*([0-9]{1,3})(?:[^0-9]|$)',
    ).firstMatch(upper);
    final koreanMatch = RegExp(
      r'(?:^|[^0-9])([0-9]{1,3})\s*항차',
    ).firstMatch(value);
    final raw = vMatch?.group(1) ?? koreanMatch?.group(1);
    final number = int.tryParse(raw ?? '');
    if (number != null && number >= 0 && number <= 999) {
      return number.toString().padLeft(2, '0');
    }

    // A file explicitly marked as BASE, VXX, or xx항차 is the V00 policy file.
    if (RegExp(r'(^|[^A-Z0-9])V?XX([^A-Z0-9]|$)', caseSensitive: false)
            .hasMatch(value) ||
        RegExp(r'xx\s*항차', caseSensitive: false).hasMatch(value) ||
        RegExp(r'(^|[^A-Z0-9])BASE([^A-Z0-9]|$)', caseSensitive: false)
            .hasMatch(value) ||
        value.contains('기본')) {
      return '00';
    }
    return null;
  }
}
