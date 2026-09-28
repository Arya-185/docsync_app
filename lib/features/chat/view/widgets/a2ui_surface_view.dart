import 'dart:convert';

// a2ui_core is genui's own model layer, declared in pubspec.yaml alongside it: the raw
// protocol message must be parsed into a core.A2uiMessage before the controller will take it.
import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../../model/a2ui_actions.dart';

/// Renders the A2UI surfaces the server composed for one assistant turn.
///
/// One of these per bubble, owning its own [SurfaceController]. That is deliberate and matches
/// the web: an action tells you which COMPONENT fired it, not which turn, so a controller
/// shared across bubbles could not attribute a tap to the right message.
///
/// The messages are composed entirely server-side (`app/ai/UiSurface.php`) — the model never
/// emits UI JSON. This widget only draws them and reports back what the user did.
///
/// Every verb except the confirm pair answers as an ordinary chat turn, so nothing here needs
/// an endpoint of its own; see [routeA2uiAction].
class A2uiSurfaceView extends StatefulWidget {
  const A2uiSurfaceView({
    super.key,
    required this.messages,
    required this.onAction,
    this.onRenderedChanged,
  });

  /// The raw protocol messages for this turn, in arrival order.
  final List<Map<String, dynamic>> messages;

  /// Called with the routed result of a widget action.
  final void Function(A2uiAction action) onAction;

  /// Reports whether anything is actually on screen.
  ///
  /// The bubble needs this to decide whether it may drop the prose a results card stands in
  /// for. "The server said it sent a surface" is NOT the same claim as "a surface rendered",
  /// and conflating the two is how the web once showed an empty bubble: the rows had been
  /// removed from the text in favour of cards that never appeared.
  final ValueChanged<bool>? onRenderedChanged;

  @override
  State<A2uiSurfaceView> createState() => _A2uiSurfaceViewState();
}

class _A2uiSurfaceViewState extends State<A2uiSurfaceView> {
  late SurfaceController _controller;

  /// Surface ids in arrival order, so the cards appear in the order the server sent them.
  final List<String> _order = [];
  final Set<String> _seen = {};

  /// Set when a message could not be applied at all. Kept so the failure is visible in the
  /// conversation rather than only in the log — a silent no-render is the exact bug this
  /// whole layer keeps producing.
  String? _error;

  int _consumed = 0;

  @override
  void initState() {
    super.initState();
    _controller = SurfaceController(catalogs: [
      // Exactly the catalog the server names in every createSurface, and the same one the web
      // renderer uses. asNoAssetCatalog drops image/audio/video, which UiSurface never emits
      // and which would otherwise need asset plumbing this app does not have.
      BasicCatalogItems.asNoAssetCatalog(),
    ]);
    _controller.surfaceUpdates.listen(_onSurfaceUpdate);
    _apply();
  }

  @override
  void didUpdateWidget(covariant A2uiSurfaceView old) {
    super.didUpdateWidget(old);
    // Messages only ever ARRIVE during a turn, so feed the controller the new tail rather than
    // rebuilding it — replaying createSurface would throw away live widget state (a half-made
    // selection) every time another token lands.
    if (widget.messages.length < _consumed) {
      _consumed = 0;
      _order.clear();
      _seen.clear();
    }
    _apply();
  }

  void _apply() {
    for (var i = _consumed; i < widget.messages.length; i++) {
      final raw = widget.messages[i];
      try {
        _controller.handleMessage(core.A2uiMessage.fromJson(_deepCopy(raw)));
      } catch (e) {
        // One bad message must not take the rest of the turn with it.
        debugPrint('[A2UI] could not apply message ${surfaceIdOf(raw)}: $e');
        _error = 'Part of this answer could not be displayed.';
      }
    }
    _consumed = widget.messages.length;
  }

  /// Hand the controller its OWN copy of every message.
  ///
  /// Measured, not defensive. genui seeds its data model with the very list object inside
  /// `updateDataModel.value`, and a selection then writes straight back into it. Without this
  /// copy, tapping a picker option MUTATES [ChatMessage.a2ui] — state the model documents as
  /// immutable and compares by identity, so nothing notices and the stored turn quietly stops
  /// matching what the server sent. The maps are a few hundred bytes; the copy is not the
  /// expensive part of drawing a surface.
  static Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  void _onSurfaceUpdate(SurfaceUpdate update) {
    if (!mounted) return;
    final id = update.surfaceId;
    setState(() {
      if (update is SurfaceRemoved) {
        _order.remove(id);
        _seen.remove(id);
      } else if (_seen.add(id)) {
        _order.add(id);
      }
    });
    widget.onRenderedChanged?.call(_order.isNotEmpty);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isEmpty && _error == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in _order)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Surface(
              surfaceContext: _controller.contextFor(id),
              actionDelegate: _DocSyncActionDelegate(widget.onAction),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Intercepts the `docsync.*` verbs before genui turns them into a model submission.
///
/// Returning true means "handled, do not submit". genui's default path would wrap the event as
/// a UiInteractionPart and hand it to an AI service — which is the right shape for a genui app
/// talking straight to a model, and the wrong one here: our surfaces answer as plain sentences
/// through the existing chat endpoint so an older client can do the same thing by typing.
class _DocSyncActionDelegate implements ActionDelegate {
  const _DocSyncActionDelegate(this.onAction);

  final void Function(A2uiAction action) onAction;

  @override
  bool handleEvent(
    BuildContext context,
    UiEvent event,
    SurfaceContext genUiContext,
    Widget Function(SurfaceDefinition, Catalog, String, DataContext) buildWidget,
  ) {
    // Not every event is a user action: a ChoicePicker selection or a DateTimeInput change
    // updates the data model and must flow on untouched, or the widget stops working.
    if (!event.isUserAction) return false;
    final action = UserActionEvent.fromMap(event.toMap());
    onAction(routeA2uiAction(action.name, action.context));
    return true;
  }
}
