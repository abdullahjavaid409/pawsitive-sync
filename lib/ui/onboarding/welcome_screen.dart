import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Introduces shared pet care and starts setup.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: StrokeIcon(
                                StrokeIconKind.paw,
                                size: 18,
                                color: scheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('PawsitiveSync', style: text.titleLarge),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          'Every dose, seen by everyone who cares for them.',
                          style: text.displaySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'One shared list. The next screen shows what a morning looks like.',
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        FilledButton(
                          onPressed: () => context.go(AppRoutes.day),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
