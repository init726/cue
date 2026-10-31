import 'package:flutter/services.dart';

class CueTravelEstimate {
  const CueTravelEstimate({
    required this.minutes,
    required this.distanceMeters,
  });
  final int minutes;
  final int distanceMeters;
}

class CueTravelEstimator {
  static const _channel = MethodChannel('cue/routes');

  Future<CueTravelEstimate?> estimate({
    required String from,
    required String to,
    required DateTime departureAt,
  }) async {
    if (from.trim().isEmpty || to.trim().isEmpty) return null;
    if (_plain(from) == _plain(to)) {
      return const CueTravelEstimate(minutes: 0, distanceMeters: 0);
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('estimateTravel', {
            'from': from.trim(),
            'to': to.trim(),
            'departureAt': departureAt.toUtc().toIso8601String(),
          });
      if (result == null) return null;
      return CueTravelEstimate(
        minutes: (result['minutes'] as num).ceil(),
        distanceMeters: (result['distanceMeters'] as num).round(),
      );
    } on PlatformException {
      return null;
    }
  }

  String _plain(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
