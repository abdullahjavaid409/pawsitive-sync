import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';

const _appTabs = [
  (StrokeIconKind.calendar, 'Today'),
  (StrokeIconKind.paw, 'Pets'),
  (StrokeIconKind.people, 'Household'),
  (StrokeIconKind.file, 'Reports'),
];

/// Keeps each tab stack alive behind one bottom bar or side rail.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  /// Tab switches happen inside branch navigators, which the root
  /// [AppRouteObserver] never sees — log them here (taps and context.go).
  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.navigationShell.currentIndex;
    final to = widget.navigationShell.currentIndex;
    if (from != to) {
      AppLog.event('nav.tab', {
        'to': _appTabs[to].$2.toLowerCase(),
        'from': _appTabs[from].$2.toLowerCase(),
      });
    }
  }

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
    final tokens = context.paws;
    return Scaffold(
      body: AdaptivePage(child: navigationShell),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaces.card,
          border: Border(top: BorderSide(color: tokens.borders.subtle)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.sm,
              tokens.spacing.sm,
              tokens.spacing.sm,
              tokens.spacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _appTabs.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == navigationShell.currentIndex,
                      label: _appTabs[i].$2,
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 58,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: i == navigationShell.currentIndex
                                      ? scheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: StrokeIcon(
                                  _appTabs[i].$1,
                                  size: 22,
                                  color: i == navigationShell.currentIndex
                                      ? tokens.states.selectedContent
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _appTabs[i].$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      fontWeight:
                                          i == navigationShell.currentIndex
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: i == navigationShell.currentIndex
                                          ? tokens.states.selectedContent
                                          : scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
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
    final tokens = context.paws;
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
              backgroundColor: tokens.surfaces.background,
              indicatorColor: tokens.states.selected,
              minWidth: 72,
              minExtendedWidth: 200,
              destinations: [
                for (final tab in _appTabs)
                  NavigationRailDestination(
                    icon: StrokeIcon(tab.$1, color: scheme.onSurfaceVariant),
                    selectedIcon: StrokeIcon(
                      tab.$1,
                      color: tokens.states.selectedContent,
                    ),
                    label: Text(tab.$2),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: tokens.borders.subtle),
            Expanded(child: AdaptivePage(child: navigationShell)),
          ],
        ),
      ),
    );
  }
}
