// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

class AppPopupButtonEntry<T> {
  const AppPopupButtonEntry({
    required this.value,
    required this.label,
    this.leading,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Widget? leading;
  final bool enabled;
}

class AppPopupButton<T> extends StatefulWidget {
  const AppPopupButton({
    super.key,
    required this.selectedValue,
    required this.entries,
    required this.onSelected,
    required this.labelBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.expand = false,
  });

  final T selectedValue;
  final List<AppPopupButtonEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final String Function(T value) labelBuilder;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool expand;

  @override
  State<AppPopupButton<T>> createState() => _AppPopupButtonState<T>();
}

class _AppPopupButtonState<T> extends State<AppPopupButton<T>> {
  bool _pressed = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final buttonColor = isDark
        ? const Color(0xFF1C1C1E)
        : Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.10),
            colorScheme.surface,
          );
    final menuColor = isDark ? const Color(0xFF141414) : colorScheme.surface;
    final borderColor = isDark
        ? const Color(0xFF323236)
        : colorScheme.primary.withValues(alpha: 0.18);
    final selectedIconColor =
        isDark ? const Color(0xFFB8B8BD) : colorScheme.primary;

    final child = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Material(
        color: buttonColor,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: () => _showMenu(menuColor, selectedIconColor),
          onHighlightChanged: (value) {
            if (_pressed != value) {
              setState(() {
                _pressed = value;
              });
            }
          },
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: colorScheme.primary.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _menuOpen
                    ? colorScheme.primary.withValues(alpha: 0.34)
                    : borderColor,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(
                    alpha: _menuOpen ? 0.16 : 0.08,
                  ),
                  blurRadius: _menuOpen ? 18 : 10,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: widget.padding,
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Flexible(
                  fit: widget.expand ? FlexFit.tight : FlexFit.loose,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(
                      widget.labelBuilder(widget.selectedValue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  turns: _menuOpen ? 0.5 : 0,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.expand) {
      return child;
    }
    return SizedBox(width: double.infinity, child: child);
  }

  Future<void> _showMenu(Color menuColor, Color selectedIconColor) async {
    setState(() {
      _menuOpen = true;
    });
    final button = context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) {
      if (mounted) {
        setState(() {
          _menuOpen = false;
        });
      }
      return;
    }

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<T>(
      context: context,
      position: position,
      elevation: 10,
      color: menuColor,
      surfaceTintColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.transparent
          : Theme.of(context).colorScheme.surfaceTint,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      items: widget.entries
          .map(
            (entry) => PopupMenuItem<T>(
              value: entry.value,
              enabled: entry.enabled,
              child: Row(
                children: [
                  if (entry.leading != null) ...[
                    entry.leading!,
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      entry.label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  if (entry.value == widget.selectedValue)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: selectedIconColor,
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _menuOpen = false;
    });
    if (result != null && result != widget.selectedValue) {
      widget.onSelected(result);
    }
  }
}
