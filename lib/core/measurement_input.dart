import 'app_language.dart';

class MeasurementInput {
 static const fields=['weight_kg','length_cm','width_cm','height_cm'];
 static bool blank(dynamic value)=>value==null||'$value'.trim().isEmpty;
 static bool empty(Map<String,dynamic> values)=>fields.every((k)=>blank(values[k]));
 static bool valid(Map<String,dynamic> values)=>empty(values)||fields.every((k){if(blank(values[k]))return false;final n=num.tryParse('${values[k]}'.replaceAll(',', '').trim());return n!=null&&n.isFinite&&n>=0;});
 static bool validEdit(Map<String,dynamic> values, Map<String,dynamic> original) {
   String normalized(dynamic value) {if(blank(value)) return ''; final text='$value'.replaceAll(',', '').trim(); final n=num.tryParse(text); return n!=null&&n.isFinite?n.toDouble().toString():text;}
   return fields.every((key)=>normalized(values[key])==normalized(original[key])) || valid(values);
 }
 static String message([AppLanguage language=AppLanguage.korean])=>language==AppLanguage.english?'Measurement data is incomplete or invalid. Enter weight, length, width and height, or leave all four blank.':language==AppLanguage.lao?'ຂໍ້ມູນນ້ຳໜັກ ແລະ ຂະໜາດບໍ່ຄົບ ຫຼື ບໍ່ຖືກຕ້ອງ. ປ້ອນນ້ຳໜັກ, ຍາວ, ກວ້າງ ແລະ ສູງໃຫ້ຄົບ ຫຼື ປະທັງໝົດວ່າງ.':'중량·크기 데이터가 정확하지 않습니다. 중량·길이·너비·높이를 모두 입력하거나 네 항목을 모두 비워 주세요.';
 static void validate(Map<String,dynamic> values,[AppLanguage language=AppLanguage.korean]){if(!valid(values))throw FormatException(message(language));}
}
