import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/color_picker.dart';
import 'package:garden_house_app/palette.dart';

void main() {
  testWidgets('swatches meet the tap target guideline', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorChooser(
            swatches: structureSwatches,
            selected: structureSwatches.first.rgb,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
