import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/measurement_input.dart';

class MeasurementWarning extends StatelessWidget {
 const MeasurementWarning({super.key,required this.weight,required this.length,required this.width,required this.height,required this.language});
 final TextEditingController weight,length,width,height;final AppLanguage language;
 @override Widget build(BuildContext context)=>AnimatedBuilder(animation:Listenable.merge([weight,length,width,height]),builder:(context,_)=>MeasurementInput.valid({'weight_kg':weight.text,'length_cm':length.text,'width_cm':width.text,'height_cm':height.text})?const SizedBox.shrink():Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(MeasurementInput.message(language),style:const TextStyle(color:Color(0xffb34816),fontSize:12))));
}
