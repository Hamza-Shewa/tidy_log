import 'package:stack_trace/stack_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

/// The trace printed in the real app session, with Flutter frames on top
/// as they appear when the error comes from a framework callback.
const _session = '''
#0      Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)
#1      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)
#2      HandleException.handleException (package:core_kit/infrastructure/network/httpHandler/handle_exception.dart:42:5)
#3      NetworkServiceImpl.requestService (package:core_kit/infrastructure/network/httpClient/network_service_impl.dart:97:14)
<asynchronous suspension>
#4      OpenSessionRepository.refreshOpenSession (package:core_kit/data/repositories/openSession/open_session_repository.dart:37:24)
<asynchronous suspension>
#5      HomePage._onTap (package:app/app/view/home_page.dart:145:12)
#6      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:345:24)
''';

void main() {
  const packages = ['app', 'core_kit'];

  test('picks the first project frame as the location, skipping SDK frames above it', () {
    final stack = trimStackText(_session, projectPackages: packages);
    expect(stack.location?.location, 'package:core_kit/infrastructure/network/httpHandler/handle_exception.dart:42:5');
    expect(stack.location?.member, 'HandleException.handleException');
    expect(stack.inProject, isTrue);
  });

  test('the trail lists the remaining project frames, with the app shown as lib/', () {
    final stack = trimStackText(_session, projectPackages: packages);
    expect(stack.trail.map((f) => f.location), [
      'package:core_kit/infrastructure/network/httpClient/network_service_impl.dart:97:14',
      'package:core_kit/data/repositories/openSession/open_session_repository.dart:37:24',
      'lib/app/view/home_page.dart:145:12',
    ]);
    expect(stack.hidden, 3, reason: '7 frames: 1 location + 3 trail, async gaps are not frames');
  });

  test('maxTrail caps the trail and counts the rest as hidden', () {
    final stack = trimStack(Trace.parse(_session), projectPackages: packages, maxTrail: 1);
    expect(stack.trail, hasLength(1));
    expect(stack.hidden, 5);
  });

  test('with no project frame, uses the first frame outside the Dart and Flutter SDKs', () {
    final stack = trimStackText(_session, projectPackages: const ['other_app']);
    expect(stack.location?.location, startsWith('package:core_kit/'));
    expect(stack.inProject, isFalse);
    expect(stack.trail, isEmpty);
  });

  test('a trace of SDK frames only falls back to the top frame', () {
    final stack = trimStackText('#0      main (dart:core/x.dart:1:1)\n', projectPackages: packages);
    expect(stack.location?.location, startsWith('dart:core'));
  });

  test('works on a live StackTrace', () {
    final stack = trimStack(Trace.from(StackTrace.current), projectPackages: const ['tidy_log']);
    expect(stack.location, isNotNull);
  });

  test('displayPath maps the app package and file URIs to lib/', () {
    expect(displayPath(Uri.parse('package:app/a/b.dart'), appPackage: 'app'), 'lib/a/b.dart');
    expect(displayPath(Uri.parse('package:dio/dio.dart'), appPackage: 'app'), 'package:dio/dio.dart');
    expect(displayPath(Uri.parse('file:///Users/me/app/lib/main.dart')), 'lib/main.dart');
  });
}
