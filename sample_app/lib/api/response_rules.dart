import 'package:tidy_log/tidy_log.dart';

/// How this app's backend reports the real result of a call, for tidy_log.
/// These only change how calls are logged; the app still reads the fields
/// itself.
final List<ResponseRule> sampleResponseRules = [
  // {"success": false, "message": "Insufficient balance"}
  ResponseRule.field('success', {true: HttpOutcome.success, false: HttpOutcome.error}, message: 'message'),
  // {"response_type": "WARNING", "messages": ["Session expires in 2 minutes"]}
  ResponseRule.field(
    'response_type',
    {'SUCCESS': HttpOutcome.success, 'INFO': HttpOutcome.info, 'WARNING': HttpOutcome.warning, 'ERROR': HttpOutcome.error},
    message: 'messages',
  ),
  // The auth service uses a numeric code: {"type": 2, "messages": [...]}.
  ResponseRule.field(
    'type',
    {1: HttpOutcome.success, 2: HttpOutcome.error},
    message: 'messages',
    when: (request) => request.path.startsWith('/api/Auth'),
  ),
];
