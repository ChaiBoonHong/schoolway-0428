import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';

@immutable
class RoleDestination {
  const RoleDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class ResponsiveRoleShell extends StatelessWidget {
  const ResponsiveRoleShell({
    required this.title,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.children,
    this.actions = const [],
    super.key,
  }) : assert(destinations.length + 1 == children.length);

  final String title;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<RoleDestination> destinations;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < SchoolWayTheme.compactBreakpoint;
    final extended = width >= SchoolWayTheme.extendedBreakpoint;
    final profileIndex = children.length - 1;
    final body = IndexedStack(index: selectedIndex, children: children);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          if (mobile)
            IconButton(
              tooltip: 'Profile',
              icon: Icon(
                selectedIndex == profileIndex
                    ? Icons.account_circle
                    : Icons.account_circle_outlined,
              ),
              onPressed: () => onDestinationSelected(profileIndex),
            ),
        ],
      ),
      body: mobile
          ? body
          : Row(
              children: [
                _RoleRail(
                  extended: extended,
                  selectedIndex: selectedIndex,
                  profileIndex: profileIndex,
                  destinations: destinations,
                  onDestinationSelected: onDestinationSelected,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: SchoolWayTheme.contentMaxWidth,
                      ),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: mobile
          ? NavigationBar(
              selectedIndex: selectedIndex == profileIndex ? 0 : selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _RoleRail extends StatelessWidget {
  const _RoleRail({
    required this.extended,
    required this.selectedIndex,
    required this.profileIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final bool extended;
  final int selectedIndex;
  final int profileIndex;
  final List<RoleDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final railSelection = selectedIndex == profileIndex ? null : selectedIndex;
    return SizedBox(
      width: extended ? 256 : 80,
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              extended: extended,
              selectedIndex: railSelection,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Tooltip(
              message: 'Profile',
              child: ListTile(
                selected: selectedIndex == profileIndex,
                leading: const Icon(Icons.account_circle_outlined),
                title: extended ? const Text('Profile') : null,
                onTap: () => onDestinationSelected(profileIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
