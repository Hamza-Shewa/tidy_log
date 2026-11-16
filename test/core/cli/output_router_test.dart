import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/output_router.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  late List<String> styled;
  late List<String> plain;
  late OutputRouter router;

  setUp(() {
    styled = [];
    plain = [];
    router = OutputRouter(pipeline: ConsolePipeline(TidyConfig()), styled: styled.add, plain: plain.add);
  });

  test('daemon JSON goes to the console byte for byte and never to the clean copy', () {
    const event = '[{"event":"app.progress","params":{"appId":"x","id":"1","message":"I/flutter (1): not a log"}}]';
    expect(router.add(event), isFalse);
    router.flush();
    expect(styled, [event]);
    expect(plain, isEmpty);
  });

  test('device log lines are restyled, and the clean copy gets plain text', () {
    expect(router.add('E/FlutterSecureStorage(9): decryption failed'), isTrue);
    router.flush();
    expect(styled.last, contains('\x1B['));
    expect(plain, ['──────── app started · pid 9 ────────', 'ERR decryption failed']);
  });

  test('JSON-looking text that is not a single-map list is treated as a log line', () {
    expect(OutputRouter.isDaemonMessage('[1, 2]'), isFalse);
    expect(OutputRouter.isDaemonMessage('[{"a":1}, {"b":2}]'), isFalse);
    expect(OutputRouter.isDaemonMessage('[not json]'), isFalse);
    expect(OutputRouter.isDaemonMessage('  [{"id":1,"result":null}]'), isTrue);
  });
}
