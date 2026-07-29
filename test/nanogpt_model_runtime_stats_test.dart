import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/nanogpt_service.dart';

void main() {
  group('NanoGptModelRuntimeStats', () {
    test('fromProvidersMap parses auto stats and uptime', () {
      final stats = NanoGptModelRuntimeStats.fromProvidersMap({
        'autoTps': 57.9,
        'autoTtftMs': 3231,
        'providers': [
          {'provider': 'a', 'available': true},
          {'provider': 'b', 'available': false},
        ],
      });
      expect(stats.tpsLabel, '57.9 TPS');
      expect(stats.ttftLabel, '3.2s TTFT');
      expect(stats.uptimePercent, 50);
      expect(stats.uptimeLabel, '50% up');
    });

    test('labels format round TPS and short TTFT', () {
      const stats = NanoGptModelRuntimeStats(tps: 58, ttftMs: 320);
      expect(stats.tpsLabel, '58 TPS');
      expect(stats.ttftLabel, '320ms TTFT');
    });
  });
}
