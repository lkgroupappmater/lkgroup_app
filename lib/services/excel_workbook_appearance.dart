import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Category colors belong to the same BASE or voyage scope as its rules.
class ExcelWorkbookAppearance {
  static Map<String, String> read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    String text(String name) {
      final file = archive.findFile(name);
      return file == null ? '' : utf8.decode(file.content as List<int>);
    }
    final styles = text('xl/styles.xml');
    if (styles.isEmpty) return {};
    final doc = XmlDocument.parse(styles);
    final dxfs = doc.findAllElements('dxfs').firstOrNull?.findElements('dxf').toList() ?? <XmlElement>[];
    final rels = <String, String>{
      for (final rel in XmlDocument.parse(text('xl/_rels/workbook.xml.rels')).findAllElements('Relationship'))
        rel.getAttribute('Id') ?? '': rel.getAttribute('Target') ?? '',
    };
    final colors = <String, String>{};
    for (final sheet in XmlDocument.parse(text('xl/workbook.xml')).findAllElements('sheet')) {
      if (sheet.getAttribute('name') != '고객 리스트') continue;
      var path = rels[sheet.getAttribute('r:id')] ?? '';
      path = path.replaceFirst(RegExp(r'^/'), '').replaceFirst(RegExp(r'^(\.\./)+'), '');
      if (!path.startsWith('xl/')) path = 'xl/$path';
      final xml = text(path);
      if (xml.isEmpty) continue;
      for (final rule in XmlDocument.parse(xml).findAllElements('cfRule')) {
        final formula = rule.findElements('formula').map((e) => e.innerText).join('');
        final kind = formula.contains('지방배송') ? 'province' : formula.contains('시내배송') ? 'city' : null;
        final id = int.tryParse(rule.getAttribute('dxfId') ?? '');
        if (kind == null || id == null || id < 0 || id >= dxfs.length) continue;
        final key = kind + (RegExp('선결[제재]').hasMatch(formula) ? '_prepaid' : '');
        final fill = dxfs[id].findAllElements('fill').firstOrNull;
        final rgb = fill?.findAllElements('fgColor').firstOrNull?.getAttribute('rgb') ?? fill?.findAllElements('bgColor').firstOrNull?.getAttribute('rgb') ?? '';
        if (RegExp(r'^(?:[A-Fa-f0-9]{2})?[A-Fa-f0-9]{6}$').hasMatch(rgb)) colors.putIfAbsent(key, () => rgb.substring(rgb.length - 6).toUpperCase());
      }
    }
    return colors;
  }
}
