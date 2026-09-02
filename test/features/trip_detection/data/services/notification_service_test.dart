import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/navigation/app_navigator.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';

/// The channel `flutter_local_notifications` talks to.
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAuditSink sink;
  late _RecordingNavigator navigator;
  late List<MethodCall> platformCalls;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
    });

    // The plugin registers its implementation from native code, which never
    // runs under `flutter test`; registering the Android one by hand is what
    // makes `show`/`cancel` resolve. Nothing must reach a real platform — the
    // point of these tests is the audit line, not the plugin — so the channel
    // it then talks to is mocked away.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          // `initialize` is typed `Future<bool>`; everything else ignores the
          // reply.
          (call) async {
            platformCalls.add(call);
            return call.method == 'initialize' ? true : null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    sink = _RecordingAuditSink();
    AuditLog.install(sink, verbose: true);
    addTearDown(AuditLog.uninstall);

    navigator = _RecordingNavigator();
    container = ProviderContainer(
      overrides: [appNavigatorProvider.overrideWithValue(navigator)],
    );
    addTearDown(container.dispose);
  });

  Future<NotificationService> service() async {
    await container.read(notificationServiceProvider.future);
    return container.read(notificationServiceProvider.notifier);
  }

  /// Payload of the last notification handed to the plugin.
  String? lastShownPayload() =>
      (platformCalls.lastWhere((c) => c.method == 'show').arguments
              as Map<Object?, Object?>)['payload']
          as String?;

  Iterable<Map<String, dynamic>> notifications() => sink.lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .where((m) => m['e'] == 'noti');

  group('NotificationService - audit instrumentation', () {
    // A ride that ends without a matching decision in the pipeline was ended
    // by hand, and the notification is the only place that shows it. The `k`
    // is a kind, never the message text — the log must not grow a second copy
    // of what is on screen.
    test('showing the trip-start notification is recorded', () async {
      await (await service()).showTripStartNotification();

      final shown = notifications().where((n) => n['k'] == 'start').single;
      expect(shown['a'], 'show');
      expect(shown.containsKey('m'), isFalse);
    });

    test('showing the trip-stop notification is recorded', () async {
      await (await service()).showTripStopNotification(
        distance: 4200,
        duration: const Duration(minutes: 18),
        avgSpeed: 4.0,
      );

      expect(
        notifications().where((n) => n['k'] == 'stop').single['a'],
        'show',
      );
    });

    test('the ongoing notification is verbose only', () async {
      AuditLog.setVerbose(verbose: false);

      await (await service()).showForegroundNotification(
        distance: 100,
        duration: const Duration(minutes: 1),
        currentSpeed: 4.0,
      );

      // One line per metrics update would swamp a normal-level log.
      expect(notifications().where((n) => n['k'] == 'fg'), isEmpty);

      AuditLog.setVerbose(verbose: true);
      await (await service()).showForegroundNotification(
        distance: 100,
        duration: const Duration(minutes: 1),
        currentSpeed: 4.0,
      );

      expect(notifications().where((n) => n['k'] == 'fg'), hasLength(1));
    });

    test('cancelling the ongoing notification is recorded', () async {
      await (await service()).cancelForegroundNotification();

      final cancelled = notifications().single;
      expect(cancelled['a'], 'cancel');
      expect(cancelled['k'], 'fg');
    });
  });

  group('NotificationService - tap routing', () {
    // A tap has no BuildContext: the payload is the only thing that says
    // where the notification points.
    test('the ongoing notification points at the tracking screen', () async {
      await (await service()).showForegroundNotification(
        distance: 100,
        duration: const Duration(minutes: 1),
        currentSpeed: 4.0,
      );
      final payload = lastShownPayload();

      (await service()).handleNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
        ),
      );

      expect(navigator.destinations, ['tracking']);
    });

    test('the trip-start notification points at the tracking screen', () async {
      await (await service()).showTripStartNotification();
      final payload = lastShownPayload();

      (await service()).handleNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
        ),
      );

      expect(navigator.destinations, ['tracking']);
    });

    test('tapping a completed trip opens its detail screen', () async {
      await (await service()).showTripStopNotification(
        distance: 4200,
        duration: const Duration(minutes: 18),
        avgSpeed: 14.0,
        tripId: 42,
      );

      (await service()).handleNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: lastShownPayload(),
        ),
      );

      expect(navigator.destinations, ['detail:42']);
    });

    // A ride that failed to persist still gets announced, with no id to open.
    test('a completed trip with no id carries no payload', () async {
      await (await service()).showTripStopNotification(
        distance: 4200,
        duration: const Duration(minutes: 18),
        avgSpeed: 14.0,
      );

      // The plugin serialises a null payload as an empty string; either way
      // the tap has no id to open and falls back to the history list.
      expect(lastShownPayload() ?? '', isEmpty);
    });

    test('the View Details action routes like a body tap', () async {
      (await service()).handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'view_details',
          payload: 'trip:7',
        ),
      );

      expect(navigator.destinations, ['detail:7']);
    });

    // Opening the app on nothing at all would read as a broken notification.
    test('a payload with no usable id falls back to the home shell', () async {
      (await service()).handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      );

      expect(navigator.destinations, ['home']);
    });

    test('a routed tap is audited', () async {
      (await service()).handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'trip:42',
        ),
      );

      final nav = notifications().where((n) => n['a'] == 'nav').single;
      expect(nav['k'], 'detail');
    });

    // Action taps still run their action and must not navigate on top of it.
    test('the stop action does not navigate', () async {
      (await service()).handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'stop',
        ),
      );

      expect(navigator.destinations, isEmpty);
    });
  });
}

/// Records where the service asked to go instead of touching a real navigator.
class _RecordingNavigator extends AppNavigator {
  _RecordingNavigator() : super(GlobalKey<NavigatorState>());

  final List<String> destinations = <String>[];

  @override
  void goToTripTracking() => destinations.add('tracking');

  @override
  void goToTripDetail(int tripId) => destinations.add('detail:$tripId');

  @override
  void goToHome() => destinations.add('home');
}

/// Collects audit lines and decodes them on demand.
class _RecordingAuditSink implements AuditSink {
  final List<String> lines = <String>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  }) => lines.add(line);

  @override
  Future<void> flush() async {}
}
