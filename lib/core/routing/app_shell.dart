import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/widgets/press_scale.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';

// v14 tab bar: calendar-check, heart, house, bar chart.
const _appTabs = [
  (StrokeIconKind.calendarCheck, 'Today'),
  (StrokeIconKind.heart, 'Pets'),
  (StrokeIconKind.home, 'Household'),
  (StrokeIconKind.chart, 'Reports'),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final current = navigationShell.currentIndex;
    // Pages scroll under the bar; its height reaches them as bottom padding.
    return Scaffold(
      extendBody: true,
      body: AdaptivePage(child: navigationShell),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            // v14 shadow-bar: one warm, soft lift (0 10 32 / 16%).
            boxShadow: const [
              BoxShadow(
                color: Color(0x294A341E),
                blurRadius: 32,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            // Frosted glass: the one floating chrome surface, like iOS.
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surfaces.card.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: dark
                        ? const Color(0x1AFFFFFF)
                        : const Color(0xB3FFFFFF),
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: [
                      for (var i = 0; i < _appTabs.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == current,
                            label: _appTabs[i].$2,
                            excludeSemantics: true,
                            child: PressScale(
                              child: GestureDetector(
                                onTap: () => onTap(i),
                                behavior: HitTestBehavior.opaque,
                                child: AnimatedContainer(
                                  duration: tokens.motion.micro,
                                  curve: Curves.easeOutCubic,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    // v14: a 7% ink wash, not a brand tint.
                                    color: i == current
                                        ? scheme.onSurface.withValues(
                                            alpha: 0.07,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      StrokeIcon(
                                        _appTabs[i].$1,
                                        size: 21,
                                        color: i == current
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _appTabs[i].$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: i == current
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: i == current
                                                  ? scheme.onSurface
                                                  : scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
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
