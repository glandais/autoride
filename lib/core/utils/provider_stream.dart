import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Bridges an `AsyncValue`-typed provider (a `@riverpod Stream<T>` function or a
/// stream notifier) into a plain [Stream] of values.
///
/// Riverpod 3 removed `provider.stream`, and calling a generated provider
/// *function* directly (`motionDataStream(ref)`) bypasses overrides and opens a
/// second, unmanaged subscription to the underlying platform stream. Listening
/// through the provider keeps a single shared subscription and lets tests inject
/// fakes with `overrideWith`.
///
/// The returned stream:
/// * emits every value the provider produces after this call,
/// * forwards provider errors as stream errors,
/// * ignores loading states,
/// * is closed when [ref] is disposed (or rebuilt).
///
/// Note: the subscription is owned by [ref], so Riverpod deactivates it while
/// nothing listens to the calling provider. That is the right default for a
/// derived stream; code that must keep running unobserved (a live trip session)
/// should subscribe on `ref.container` instead — see `TripRecorderService`.
Stream<T> streamFromProvider<T>(
  Ref ref,
  ProviderListenable<AsyncValue<T>> provider,
) {
  final controller = StreamController<T>();

  final subscription = ref.listen<AsyncValue<T>>(provider, (previous, next) {
    if (controller.isClosed) return;
    next.when(data: controller.add, error: controller.addError, loading: () {});
  });

  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  return controller.stream;
}
