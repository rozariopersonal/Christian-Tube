import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/widgets/reader_selection_toolbar.dart';
import 'package:mobile/shared/ui/double_tap_dictionary_area.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('copy writes the selected reader text to the clipboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: Scaffold(
          body: Center(
              child: DoubleTapDictionaryArea(
        contextMenuBuilder: (context, state, selectedText) =>
            buildReaderSelectionToolbar(context, state, 1,
                selectedText: selectedText, onHighlight: (_, __) {}),
        child: const Text('Grace'),
      ))),
    ));
    await tester.longPress(find.text('Grace'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Grace');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
