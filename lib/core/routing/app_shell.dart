import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (StrokeIconKind.calendar, 'Today'),
    (StrokeIconKind.paw, 'Pets'),
    (StrokeIconKind.people, 'Household'),
    (StrokeIconKind.file, 'Reports'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor: Colors.transparent,
              destinations: [
                for (final tab in _tabs)
                  NavigationRailDestination(
                    icon: StrokeIcon(
                      tab.$1,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    selectedIcon: StrokeIcon(
                      tab.$1,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: Text(tab.$2),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => _go(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          StrokeIcon(
                            _tabs[i].$1,
                            color: i == navigationShell.currentIndex
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tabs[i].$2,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 11,
                                  fontWeight: i == navigationShell.currentIndex
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: i == navigationShell.currentIndex
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
