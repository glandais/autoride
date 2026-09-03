import 'dart:convert';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditEvent.encode', () {
    test('round-trips through jsonDecode with t and e set', () {
      final line = AuditEvent.encode(1756800012345, AuditEvent.trip, {
        'a': 'stop',
        'id': 42,
        'dist': 8421.34,
      });

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['t'], 1756800012345);
      expect(decoded['e'], 'trip');
      expect(decoded['a'], 'stop');
      expect(decoded['id'], 42);
      expect(decoded['dist'], 8421.34);
    });

    test('keeps 7 decimals for coordinates and 3 for everything else', () {
      final line = AuditEvent.encode(1, AuditEvent.fix, {
        'lat': 47.21843123456789,
        'lon': -1.55356214999,
        'sp': 3.2149999999,
        'ac': 6.44444,
      });

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['lat'], 47.2184312);
      expect(decoded['lon'], -1.5535621);
      expect(decoded['sp'], 3.215);
      expect(decoded['ac'], 6.444);
    });

    test('drops null fields rather than writing them out', () {
      final line = AuditEvent.encode(1, AuditEvent.trip, {
        'id': 7,
        'conf': null,
      });

      expect(line, isNot(contains('conf')));
      expect(jsonDecode(line), containsPair('id', 7));
    });

    test('drops non-finite doubles instead of throwing', () {
      // A provider with no value can hand us NaN, and NaN is not JSON.
      final line = AuditEvent.encode(1, AuditEvent.fix, {
        'sp': double.nan,
        'al': double.infinity,
        'lat': 47.0,
      });

      expect(() => jsonDecode(line), returnsNormally);
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded.containsKey('sp'), isFalse);
      expect(decoded.containsKey('al'), isFalse);
      expect(decoded['lat'], 47);
    });

    test('converts DateTime, Duration and enums to compact primitives', () {
      final line = AuditEvent.encode(1, AuditEvent.gpsWatchdog, {
        'ts': DateTime.fromMillisecondsSinceEpoch(1756799982000),
        'el': const Duration(seconds: 612),
        'lv': _Level.warning,
      });

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['ts'], 1756799982000);
      expect(decoded['el'], 612000);
      expect(decoded['lv'], 'warning');
    });

    test('truncates a long string so one line cannot eat the budget', () {
      final line = AuditEvent.encode(1, AuditEvent.error, {'m': 'x' * 5000});

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(
        (decoded['m'] as String).length,
        AuditEvent.maxStringLength + 1, // + the ellipsis
      );
    });

    test('escapes quotes and accents rather than breaking the line', () {
      final line = AuditEvent.encode(1, AuditEvent.log, {
        'm': 'Trip "42" arrêté — 8 km',
      });

      expect(line.split('\n'), hasLength(1));
      expect(jsonDecode(line), containsPair('m', 'Trip "42" arrêté — 8 km'));
    });
  });

  group('the type vocabulary', () {
    test('has no duplicate short codes', () {
      expect(AuditEvent.all.toSet(), hasLength(AuditEvent.all.length));
    });

    test('codes stay short enough to be worth shortening', () {
      for (final type in AuditEvent.all) {
        expect(type.length, lessThanOrEqualTo(5), reason: type);
        expect(type, isNotEmpty);
      }
    });
  });

  group('AuditSchema.thresholds', () {
    // A detection constant added without being exposed here means the next log
    // is missing the number needed to read it — and nothing else would notice.
    test('exposes every threshold the analysis side relies on', () {
      final keys = AuditSchema.thresholds().keys.toSet();

      expect(
        keys,
        containsAll(<String>[
          'cycMin',
          'cycMax',
          'maxKmh',
          'gpsIdle',
          'gpsLoss',
          'gpsAge',
          'conf',
          'nDet',
          'detWin',
          'detTo',
          'evalMs',
          'cool',
          'wMot',
          'wSpd',
          'spAcc',
          'spAge',
          'dspMin',
          'dspFac',
          'winMs',
          'winMax',
          'sdMax',
          'gyMax',
          'staKmh',
          'movKmh',
          'minPause',
          'maxPause',
          'resume',
          'nSta',
          'hyst',
          'rpDist',
          'rpAcc',
          'rpBuf',
          'recInt',
          'minTrip',
          'preBufS',
          'preBufN',
          'hzN',
          'hzM',
          'hzL',
          'hzC',
          'dfCyc',
          'dfMov',
          'dfLow',
          'dfCrit',
          'batCrit',
          'batLow',
          'batMed',
        ]),
      );
    });

    test('carries the real constants, and encodes without loss', () {
      final line = AuditEvent.encode(1, AuditEvent.header, {
        'sv': AuditSchema.version,
        'k': AuditSchema.thresholds(),
      });

      final decoded = jsonDecode(line) as Map<String, dynamic>;
      final k = decoded['k'] as Map<String, dynamic>;
      expect(decoded['sv'], 2);
      expect(k['cycMin'], 8);
      expect(k['gpsLoss'], 600);
      expect(k['conf'], 0.7);
      expect(k['sdMax'], 0.8);
      expect(k['minTrip'], 60);
    });
  });
}

enum _Level { warning }
