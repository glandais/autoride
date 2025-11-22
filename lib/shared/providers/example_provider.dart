import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'example_provider.g.dart';

/// Simple counter provider example
/// Demonstrates basic @riverpod annotation usage
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
  void reset() => state = 0;
}

/// Simple value provider example
/// Auto-disposed when no longer used
@riverpod
String welcomeMessage(Ref ref) {
  return 'Welcome to AutoRide!';
}

/// Provider with parameters (family pattern)
/// Auto-disposed by default
@riverpod
int multiply(Ref ref, int value, int multiplier) {
  return value * multiplier;
}
