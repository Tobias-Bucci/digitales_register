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

import 'dart:typed_data';

import 'package:dr/middleware/middleware.dart';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    this.size = 44,
  });

  final String? imageUrl;
  final double size;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  static final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};

  Uint8List? _imageBytes;
  String? _lastRequestedUrl;
  bool _isResolving = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _resolveImage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolveImage(widget.imageUrl);
    }
  }

  Future<void> _resolveImage(String? imageUrl) async {
    _lastRequestedUrl = imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _isResolving = false;
        _hasError = false;
      });
      return;
    }

    final cached = _memoryCache[imageUrl];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _imageBytes = cached;
        _isResolving = false;
        _hasError = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isResolving = true;
      _hasError = false;
    });

    try {
      final bytes = await fetchAuthenticatedBytes(imageUrl);
      if (!mounted || _lastRequestedUrl != imageUrl) {
        return;
      }
      if (bytes.isEmpty) {
        setState(() {
          _imageBytes = null;
          _isResolving = false;
          _hasError = true;
        });
        return;
      }
      _memoryCache[imageUrl] = bytes;
      setState(() {
        _imageBytes = bytes;
        _isResolving = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted || _lastRequestedUrl != imageUrl) {
        return;
      }
      setState(() {
        _imageBytes = null;
        _isResolving = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Icon(
        Icons.person_rounded,
        color: colorScheme.primary,
        size: widget.size * 0.56,
      ),
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          placeholder,
          if (_imageBytes != null)
            ClipOval(
              child: Image.memory(
                _imageBytes!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          if (_isResolving && _imageBytes == null)
            SizedBox(
              width: widget.size * 0.42,
              height: widget.size * 0.42,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.primary.withValues(alpha: 0.72),
                ),
              ),
            ),
          if (_hasError && _imageBytes == null)
            Icon(
              Icons.person_rounded,
              color: colorScheme.primary,
              size: widget.size * 0.56,
            ),
        ],
      ),
    );
  }
}
