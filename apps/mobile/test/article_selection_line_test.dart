import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/ui/reader_selection_line.dart';
import 'package:mobile/shared/ui/double_tap_dictionary_area.dart';
import 'package:mobile/features/books/widgets/reader_selection_toolbar.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reports the range only for the selected article line',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ranges = <int, SelectedContentRange?>{};
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Scaffold(
            body: DoubleTapDictionaryArea(
          contextMenuBuilder: (context, state, text) =>
              buildReaderSelectionToolbar(context, state, 1,
                  selectedText: text, onHighlight: (_, __) {}),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 2; i++)
              ReaderSelectionLine(
                onSelection: (range) => ranges[i] = range,
                child: const Text('Grace'),
              ),
          ])),
        ))));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Grace').last);
    await tester.pumpAndSettle();
    expect(ranges[1]?.startOffset, 0);
    expect(ranges[1]?.endOffset, 5);
    expect(ranges[0], isNull);
  });
}
