import 'package:flutter/material.dart';

import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';

/// Activities a *recorded* trip can carry.
///
/// `stationary` is excluded on purpose: a stationary trip is not something the
/// recorder ever writes, so offering it would be a filter that always returns
/// an empty list.
const _filterableActivities = <ActivityType>[
  ActivityType.cycling,
  ActivityType.walking,
  ActivityType.running,
  ActivityType.driving,
  ActivityType.unknown,
];

/// Ask the user which trips the history list should show.
///
/// Returns the chosen [TripFilter], or `null` if the dialog was dismissed
/// without applying — which is *not* the same as an empty filter, so callers
/// must leave the current one alone on `null`.
Future<TripFilter?> showTripFilterDialog(
  BuildContext context, {
  required TripFilter current,
}) {
  return showDialog<TripFilter>(
    context: context,
    builder: (context) => TripFilterDialog(initialFilter: current),
  );
}

/// The filter dialog itself. Edits a local copy; nothing is applied until the
/// user presses Apply.
class TripFilterDialog extends StatefulWidget {
  const TripFilterDialog({required this.initialFilter, super.key});

  final TripFilter initialFilter;

  @override
  State<TripFilterDialog> createState() => _TripFilterDialogState();
}

class _TripFilterDialogState extends State<TripFilterDialog> {
  late TripFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Filter Trips'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectionLabel('Period', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final range in TripDateRange.values)
                  ChoiceChip(
                    label: Text(range.label),
                    selected: _filter.dateRange == range,
                    onSelected: (_) => setState(() {
                      _filter = _filter.copyWith(dateRange: range);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            _SectionLabel('Activity', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter.activity == null,
                  // `copyWith` cannot write a null back, so the reset goes
                  // through a fresh value that keeps the other criteria.
                  onSelected: (_) => setState(() {
                    _filter = TripFilter(
                      confirmedOnly: _filter.confirmedOnly,
                      dateRange: _filter.dateRange,
                    );
                  }),
                ),
                for (final activity in _filterableActivities)
                  ChoiceChip(
                    label: Text(activity.label),
                    selected: _filter.activity == activity,
                    onSelected: (_) => setState(() {
                      _filter = _filter.copyWith(activity: activity);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirmed trips only'),
              value: _filter.confirmedOnly,
              onChanged: (value) => setState(() {
                _filter = _filter.copyWith(confirmedOnly: value);
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const TripFilter()),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _filter),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: style),
  );
}
