import 'package:docsync_app/features/chat/model/task_file_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTaskFileViewUrl', () {
    test('the task page View link', () {
      expect(isTaskFileViewUrl(Uri.parse(
          'https://ak.aryamehta.com/app/doc_readiness.php?action=view&task_id=512&file_id=88')), isTrue);
    });
    test('other actions and pages stay in the WebView', () {
      for (final u in [
        'https://ak.aryamehta.com/app/doc_readiness.php?action=files&task_id=512',
        'https://ak.aryamehta.com/app/doc_readiness.php?ids=1,2',
        'https://ak.aryamehta.com/app/view_task_history.php?action=view&task_id=1&file_id=2',
        'https://ak.aryamehta.com/app/doc_readiness.php?action=view&task_id=0&file_id=2',
        'https://ak.aryamehta.com/app/doc_readiness.php?action=view&task_id=5&file_id=x',
        'https://ak.aryamehta.com/app/doc_readiness.php?action=view&task_id=5',
      ]) {
        expect(isTaskFileViewUrl(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  group('fileNameFrom', () {
    test('quoted and bare', () {
      expect(fileNameFrom('inline; filename="Form 16 FY25.pdf"'), 'Form 16 FY25.pdf');
      expect(fileNameFrom('inline; filename=stmt.pdf'), 'stmt.pdf');
    });
    test('no path tricks, nothing usable', () {
      expect(fileNameFrom('inline; filename="../x/y.pdf"'), '.._x_y.pdf');
      expect(fileNameFrom('inline; filename=".."'), isNull);
      expect(fileNameFrom('inline'), isNull);
      expect(fileNameFrom(null), isNull);
    });
  });

  group('refusalText', () {
    test('the server refusal page sentence', () {
      const page = '<!doctype html><meta charset="utf-8"><title>DocSync</title><body>'
          '<p>You do not have permission to download this client&#039;s files.</p></body>';
      expect(refusalText(page), "You do not have permission to download this client's files.");
    });
    test('lost session JSON', () {
      expect(refusalText('{"ok":false,"error":"not_authenticated"}'), contains('sign in'));
    });
    test('unknown body', () {
      expect(refusalText('oops'), isNull);
    });
  });
}
