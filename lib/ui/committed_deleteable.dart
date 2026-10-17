import 'package:flutter/material.dart';

/// An accepted deletion is committed once, on animation completion OR teardown.
/// Unlike a raw TickerFuture, cancellation cannot strand the data callback.
class CommittedDeleteable extends StatefulWidget {
  const CommittedDeleteable({
    super.key,
    required this.builder,
    required this.onDeleted,
    this.showEntryAnimation = true,
    this.showExitAnimation = true,
    this.duration = const Duration(milliseconds: 250),
  });

  final Widget Function(BuildContext, Future<void> Function()) builder;
  final VoidCallback onDeleted;
  final bool showEntryAnimation;
  final bool showExitAnimation;
  final Duration duration;

  @override
  State<CommittedDeleteable> createState() => _CommittedDeleteableState();
}

class _CommittedDeleteableState extends State<CommittedDeleteable>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: widget.showEntryAnimation ? 0 : 1,
  );
  Future<void>? _deletion;

  @override
  void initState() {
    super.initState();
    if (widget.showEntryAnimation) {
      _controller.animateTo(1, duration: widget.duration, curve: Curves.ease);
    }
  }

  Future<void> _delete() {
    final onDeleted = widget.onDeleted;
    // Store the operation before running any callback, including no-animation
    // deletes. Repeated taps and rebuilds share the same accepted operation.
    return _deletion ??= Future<void>.microtask(() => _commit(onDeleted));
  }

  Future<void> _commit(VoidCallback onDeleted) async {
    try {
      if (mounted && widget.showExitAnimation) {
        await _controller
            .animateTo(0, duration: widget.duration, curve: Curves.ease)
            .orCancel;
      }
    } on TickerCanceled {
      // Teardown ends the visual effect, but cannot revoke an accepted delete.
    } finally {
      // Resumes outside dispose's locked widget tree, even on cancellation.
      onDeleted();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizeTransition(
      sizeFactor: _controller,
      child: widget.builder(context, _delete),
    );
  }
}
