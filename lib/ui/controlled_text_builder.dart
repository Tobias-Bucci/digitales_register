import 'package:flutter/material.dart';

/// Owns a text controller for the entire lifetime of its subtree, including
/// dialog exit transitions after showDialog's result has completed.
class ControlledTextBuilder extends StatefulWidget {
  const ControlledTextBuilder({
    super.key,
    this.initialText = '',
    required this.builder,
  });

  final String initialText;
  final Widget Function(BuildContext, TextEditingController) builder;

  @override
  State<ControlledTextBuilder> createState() => _ControlledTextBuilderState();
}

class _ControlledTextBuilderState extends State<ControlledTextBuilder> {
  late final _controller = TextEditingController(text: widget.initialText)
    ..addListener(_onChanged);

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
