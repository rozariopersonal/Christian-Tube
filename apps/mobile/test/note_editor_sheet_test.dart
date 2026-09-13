import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/ui/note_editor_sheet.dart';

void main() {
  testWidgets('NoteEditorSheet layout test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoteEditorSheet(
            title: 'Test',
            initialText: 'Hello',
          ),
        ),
      ),
    );
    expect(find.byType(NoteEditorSheet), findsOneWidget);
  });
}
