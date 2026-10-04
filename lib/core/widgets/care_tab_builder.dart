import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:provider/provider.dart';

/// Rebuilds [builder] on [CareRepository] changes only while it is visible.
///
/// The tab shell (StatefulShellRoute.indexedStack) keeps every tab mounted,
/// and routes under a pushed page stay mounted too; both sit under
/// `TickerMode(enabled: false)`. With a plain `context.watch`, every change
/// (each dose, each sync start/finish) rebuilt all four tabs and recomputed
/// reports nobody was looking at. Hidden screens now skip those rebuilds
/// and catch up once, when they are shown again.
class CareTabBuilder extends StatefulWidget {
  const CareTabBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, CareRepository care) builder;

  @override
  State<CareTabBuilder> createState() => _CareTabBuilderState();
}

class _CareTabBuilderState extends State<CareTabBuilder> {
  CareRepository? _care;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider instance is fixed for the app's life; listen manually so
    // hidden screens can skip rebuilds.
    final care = Provider.of<CareRepository>(context, listen: false);
    if (!identical(care, _care)) {
      _care?.removeListener(_onCareChanged);
      _care = care..addListener(_onCareChanged);
    }
    // Depends on TickerMode, so showing the screen again runs this and then
    // build() with the latest data.
    _visible = TickerMode.of(context);
  }

  void _onCareChanged() {
    if (!mounted) return;
    // Hidden: skip. Becoming visible changes TickerMode, which rebuilds.
    if (_visible) setState(() {});
  }

  @override
  void dispose() {
    _care?.removeListener(_onCareChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _care!);
}
