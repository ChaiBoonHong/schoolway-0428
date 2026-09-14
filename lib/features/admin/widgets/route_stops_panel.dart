import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';

/// Ordered stop list for the admin route planner editor. Supports drag
/// reorder, per-stop removal, tap-to-center, and flags plans that exceed the
/// Google Compute Routes stop limit.
class RouteStopsPanel extends StatelessWidget {
  const RouteStopsPanel({
    super.key,
    required this.stops,
    required this.onReorder,
    required this.onRemove,
    required this.onSelect,
    required this.onClose,
    this.maxStops = maxPlannedRouteStops,
    this.finalStopIsSchool = false,
  });

  final List<RouteWaypoint> stops;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;
  final void Function(int index) onSelect;
  final VoidCallback onClose;
  final int maxStops;
  final bool finalStopIsSchool;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (_) {},
      child: Material(
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_numbered,
                    size: 18,
                    color: SchoolWayTheme.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.routeStopsPanelTitle,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                  ),
                  Text(
                    strings.routeStopCounter(stops.length, maxStops),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: stops.length > maxStops
                          ? SchoolWayTheme.danger
                          : SchoolWayTheme.blueGrey,
                    ),
                  ),
                  IconButton(
                    tooltip: strings.close,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: SchoolWayTheme.blueGrey,
                    ),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            if (stops.length > maxStops)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: SchoolWayTheme.warning,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.routeTooManyStopsForGoogle(
                          stops.length,
                          maxStops,
                        ),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          height: 1.35,
                          color: SchoolWayTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: stops.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (oldIndex != newIndex) onReorder(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  final isSchool =
                      finalStopIsSchool && index == stops.length - 1;
                  return ListTile(
                    key: ValueKey(
                      'planner-stop-$index-${stop.latitude}-'
                      '${stop.longitude}',
                    ),
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          stops.length > maxStops || index >= maxStops
                          ? SchoolWayTheme.warning
                          : SchoolWayTheme.primary,
                      child: isSchool
                          ? Icon(
                              Icons.school,
                              size: 16,
                              color: SchoolWayTheme.surface,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: SchoolWayTheme.surface,
                              ),
                            ),
                    ),
                    title: Text(
                      isSchool
                          ? strings.schoolRouteEndpoint
                          : strings.routeStopNumber(index + 1),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                    subtitle: Text(
                      '${stop.latitude.toStringAsFixed(5)}, '
                      '${stop.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                    trailing: isSchool
                        ? Semantics(
                            container: true,
                            label: strings.schoolRouteEndpointLocked,
                            child: Icon(
                              Icons.lock_outline,
                              color: SchoolWayTheme.blueGrey,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: strings.removeStopTooltip,
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: SchoolWayTheme.danger,
                                ),
                                onPressed: () => onRemove(index),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Tooltip(
                                  message: strings.reorderStopTooltip,
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Icon(
                                      Icons.drag_handle,
                                      color: SchoolWayTheme.blueGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    onTap: () => onSelect(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
