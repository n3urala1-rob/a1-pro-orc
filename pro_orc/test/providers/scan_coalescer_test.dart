import 'package:test/test.dart';

import 'package:pro_orc/providers/projects_provider.dart';

void main() {
  group('ScanCoalescer', () {
    test('requestRescan runs immediately when idle', () {
      final coalescer = ScanCoalescer();
      var ran = 0;

      coalescer.requestRescan(() => ran++);

      expect(ran, equals(1));
      expect(coalescer.hasPendingRescan, isFalse);
    });

    test(
      'requestRescan while scanning defers instead of running immediately',
      () {
        final coalescer = ScanCoalescer();
        var ran = 0;

        coalescer.markScanStarted();
        coalescer.requestRescan(() => ran++);

        expect(ran, equals(0), reason: 'must not run while scan is in flight');
        expect(coalescer.hasPendingRescan, isTrue);
      },
    );

    test(
      'multiple requests while scanning collapse into exactly one follow-up',
      () {
        final coalescer = ScanCoalescer();
        var ran = 0;

        coalescer.markScanStarted();
        coalescer.requestRescan(() => ran++);
        coalescer.requestRescan(() => ran++);
        coalescer.requestRescan(() => ran++);
        coalescer.requestRescan(() => ran++);

        expect(ran, equals(0));

        var followUps = 0;
        coalescer.markScanFinished(() => followUps++);

        expect(
          followUps,
          equals(1),
          reason:
              'four requests during one scan must yield exactly one '
              'follow-up scan, not four',
        );
      },
    );

    test('markScanFinished with no pending request runs nothing', () {
      final coalescer = ScanCoalescer();
      var ran = 0;

      coalescer.markScanStarted();
      coalescer.markScanFinished(() => ran++);

      expect(ran, equals(0));
      expect(coalescer.isScanning, isFalse);
    });

    test('a request after markScanFinished starts a fresh cycle', () {
      final coalescer = ScanCoalescer();

      coalescer.markScanStarted();
      coalescer.markScanFinished(() {});
      expect(coalescer.isScanning, isFalse);

      var ran = 0;
      coalescer.requestRescan(() => ran++);
      expect(
        ran,
        equals(1),
        reason: 'idle again, so this should run immediately',
      );
    });
  });
}
