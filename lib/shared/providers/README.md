# Shared Providers

Global providers used across multiple features.

## Provider Patterns

### Simple Value Provider
Use `@riverpod` for functions that return a value:

```dart
@riverpod
String myValue(MyValueRef ref) {
  return 'Hello';
}
```

Usage: `ref.watch(myValueProvider)`

### Class-Based Provider (Notifier)
Use `@riverpod` with a class for stateful logic:

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
```

Usage:
- Watch state: `ref.watch(counterProvider)`
- Call methods: `ref.read(counterProvider.notifier).increment()`

### Family Provider (with parameters)
Use parameters for computed providers:

```dart
@riverpod
int multiply(MultiplyRef ref, int a, int b) {
  return a * b;
}
```

Usage: `ref.watch(multiplyProvider(5, 3))`

### AutoDispose vs KeepAlive

**AutoDispose (default)**: Provider is disposed when no longer watched
```dart
@riverpod
class MyProvider extends _$MyProvider {
  // Auto-disposed by default
}
```

**KeepAlive**: Provider stays in memory
```dart
@Riverpod(keepAlive: true)
class MyProvider extends _$MyProvider {
  // Never disposed
}
```

## Code Generation Workflow

### Initial Generation
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Watch Mode (Development)
```bash
flutter pub run build_runner watch --delete-conflicting-outputs
```

### Clean Generated Files
```bash
flutter pub run build_runner clean
```

## Best Practices

1. **Always use `part` directive**: Include `part 'filename.g.dart';`
2. **Run generation after changes**: Code won't compile without generated files
3. **Use watch mode during development**: Automatic regeneration on save
4. **AutoDispose for UI state**: Prevents memory leaks
5. **KeepAlive for persistent data**: Settings, authentication, active trip
6. **Top-level providers only**: Never create providers inside widgets
7. **Use ref.watch in build()**: For reactive updates
8. **Use ref.read for callbacks**: For one-time reads in event handlers

## Common Issues

### "part 'file.g.dart' not found"
**Solution**: Run `flutter pub run build_runner build --delete-conflicting-outputs`

### "The class '_$MyProvider' can't be found"
**Solution**: Ensure you've run code generation and the `.g.dart` file exists

### Generated file is outdated
**Solution**: Use `--delete-conflicting-outputs` flag or run `build_runner clean` first

### Changes not reflected
**Solution**: Stop watch mode, run clean, then run build again
