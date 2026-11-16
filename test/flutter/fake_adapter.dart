import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers every request with [status] and [body], or fails with [error].
final class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({this.status = 200, this.body = '{}', this.error, this.contentType = 'application/json'});

  final int status;
  final String body;
  final Object? error;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (error != null) throw error!;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
