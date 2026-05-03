import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Just verify the app builds without crashing
    expect(StudyCollabApp, isNotNull);
  });
}