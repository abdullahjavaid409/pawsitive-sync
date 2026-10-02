import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Keeps each tab stack alive and hides the bottom bar on Reports.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = AdaptiveLayout.classify(constraints.maxWidth);
        if (window == WindowClass.compact) {
          return _CompactShell(navigationShell: navigationShell, onTap: _go);
        }
        return _WideShell(
          navigationShell: navigationShell,
          extended: window == WindowClass.expanded,
          onTap: _go,
        );
      },
    );
  }

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.navigationShell, required this.onTap});

  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showBar = navigationShell.currentIndex != 3;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: showBar
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      for (var i = 0; i < AppShell._tabs.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == navigationShell.currentIndex,
                            label: AppShell._tabs[i].$2,
                            child: InkWell(
                              onTap: () => onTap(i),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  StrokeIcon(
                                    AppShell._tabs[i].$1,
                                    color: i == navigationShell.currentIndex
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppShell._tabs[i].$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontSize: 11,
                                          fontWeight:
                                              i == navigationShell.currentIndex
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color:
                                              i == navigationShell.currentIndex
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.navigationShell,
    required this.extended,
    required this.onTap,
  });

  final StatefulNavigationShell navigationShell;
  final bool extended;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: onTap,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              backgroundColor: scheme.surface,
              indicatorColor: Colors.transparent,
              destinations: [
                for (final tab in AppShell._tabs)
                  NavigationRailDestination(
                    icon: StrokeIcon(tab.$1, color: scheme.onSurfaceVariant),
                    selectedIcon: StrokeIcon(tab.$1, color: scheme.primary),
                    label: Text(tab.$2),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: AdaptivePage(child: navigationShell)),
          ],
        ),
      ),
    );
  }
}
