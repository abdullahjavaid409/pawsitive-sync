import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The text-field context menu every field in the app uses.
///
/// On iOS 16+ it keeps the native edit menu (Copy, Paste, Look Up…) so
/// pasting never shows the "Allow Paste" prompt. Elsewhere it falls back
/// to Flutter's adaptive toolbar, same as the framework default.
///
/// Why not the framework default: Flutter's `SystemContextMenu` gives
/// every menu its own controller. When a field re-shows its menu (double
/// tap, drag a handle, switch fields) the new menu builds before the old
/// one is disposed, and a debug assertion fires ("Attempted to show while
/// another instance was still visible"). Release builds are unaffected,
/// but the noise hides real errors. One shared controller removes the race.
/// Drop this once the framework fixes it.
Widget appContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return _SharedSystemContextMenu(editableTextState: editableTextState);
  }
  return AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}

class _SharedSystemContextMenu extends StatefulWidget {
  const _SharedSystemContextMenu({required this.editableTextState});

  final EditableTextState editableTextState;

  @override
  State<_SharedSystemContextMenu> createState() =>
      _SharedSystemContextMenuState();
}

class _SharedSystemContextMenuState extends State<_SharedSystemContextMenu> {
  /// The menu that most recently asked to be shown. Only it may hide the
  /// native menu, so a stale menu disposing late can't close a new one.
  static _SharedSystemContextMenuState? _owner;

  /// App-lifetime, never disposed: there is only ever one native menu.
  static final _controller = SystemContextMenuController(
    // The user dismissed the native menu: drop the Flutter-side toolbar
    // too, keeping the selection handles, as the framework does.
    onSystemHide: () => _owner?.widget.editableTextState.hideToolbar(false),
  );

  @override
  void dispose() {
    if (identical(_owner, this)) {
      _owner = null;
      _controller.hide();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.editableTextState;
    final items = SystemContextMenu.getDefaultItems(field);
    if (items.isNotEmpty) {
      final (:startGlyphHeight, :endGlyphHeight) = field.getGlyphHeights();
      final anchor = TextSelectionToolbarAnchors.getSelectionRect(
        field.renderEditable,
        startGlyphHeight,
        endGlyphHeight,
        field.renderEditable.getEndpointsForSelection(
          field.textEditingValue.selection,
        ),
      );
      final localizations = WidgetsLocalizations.of(context);
      _owner = this;
      _controller.showWithItems(anchor, [
        for (final item in items) item.getData(localizations),
      ]);
    }
    return const SizedBox.shrink();
  }
}
