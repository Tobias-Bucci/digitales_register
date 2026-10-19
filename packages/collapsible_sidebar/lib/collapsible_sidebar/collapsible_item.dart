import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class CollapsibleItem {
  CollapsibleItem({
    this.hasDivider = false,
    this.builder,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.isSelected = false,
  });

  final Widget Function(Widget child)? builder;
  final String text;
  final IconData icon;
  final Function onPressed;
  bool isSelected;
  final bool hasDivider;
}
