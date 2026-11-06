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

import 'dart:async';

import 'package:dr/middleware/middleware.dart';
import 'package:dr/profile_picture.dart';
import 'package:flutter/material.dart';

/// The profile picture, or a figure for as long as there is none to show.
///
/// The figure is what stands whenever the picture is missing, loading, cannot be
/// decoded or belongs to nobody yet, so the avatar is never just empty. It lives
/// for as long as the app in the navigation of the new design, so it has to find
/// its way to the picture by itself: it tries again after a failure and whenever
/// [profilePictureRetries] says that the reason may be gone.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    this.size = 44,
    this.showProgress = true,
  });

  static const pictureKey = Key('profile-avatar-picture');
  static const figureKey = Key('profile-avatar-figure');

  /// How long to wait after each failure in a row. After the last one, only
  /// [profilePictureRetries] or a new address starts another attempt.
  @visibleForTesting
  static const retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final String? imageUrl;
  final double size;

  /// Whether a load shows as a spinner instead of the figure. Off in places that
  /// have to stay calm, such as the navigation bar.
  final bool showProgress;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  MemoryImage? _picture;
  bool _isResolving = false;
  int _failures = 0;
  Timer? _retry;

  /// Which load is the current one. A later answer of another one is dropped.
  int _load = 0;

  @override
  void initState() {
    super.initState();
    profilePictureRetries.addListener(_retryNow);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  @override
  void dispose() {
    profilePictureRetries.removeListener(_retryNow);
    _retry?.cancel();
    super.dispose();
  }

  /// Starts over for a new address. What was shown belonged to the old one, and
  /// that may have been another account.
  void _resolve() {
    final url = widget.imageUrl;
    final known = url == null || url.isEmpty;
    _picture = known ? null : cachedProfilePicture(url);
    _failures = 0;
    _retry?.cancel();
    _load++;
    _isResolving = !known && _picture == null;
    if (_isResolving) unawaited(_fetch(url!));
  }

  void _retryNow() {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty || _isResolving) return;
    if (cachedProfilePicture(url) != null) return;
    _failures = 0;
    _retry?.cancel();
    setState(() => _isResolving = true);
    unawaited(_fetch(url));
  }

  Future<void> _fetch(String url) async {
    final load = ++_load;
    try {
      final bytes = await fetchAuthenticatedBytes(url);
      if (!mounted || load != _load) return;
      final picture = MemoryImage(bytes);
      var decodes = true;
      // Also decodes it ahead of the first frame that shows it.
      await precacheImage(
        picture,
        context,
        onError: (_, __) => decodes = false,
      );
      if (!mounted || load != _load) return;
      if (!decodes) throw const FormatException('No image');
      cacheProfilePicture(url, picture);
      setState(() {
        _picture = picture;
        _isResolving = false;
        _failures = 0;
      });
    } catch (_) {
      if (!mounted || load != _load) return;
      setState(() => _isResolving = false);
      if (_failures < ProfileAvatar.retryDelays.length) {
        final delay = ProfileAvatar.retryDelays[_failures++];
        _retry = Timer(delay, () {
          if (!mounted || load != _load) return;
          setState(() => _isResolving = true);
          unawaited(_fetch(url));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    if (picture == null) return _buildFigure(context);
    return ClipOval(
      child: Image(
        key: ProfileAvatar.pictureKey,
        image: picture,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // The image cache may have let go of it in the meantime.
        frameBuilder: (context, child, frame, synchronous) =>
            frame == null && !synchronous ? _buildFigure(context) : child,
        errorBuilder: (context, _, __) => _buildFigure(context),
      ),
    );
  }

  Widget _buildFigure(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: ProfileAvatar.figureKey,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      alignment: Alignment.center,
      child: _isResolving && widget.showProgress
          ? SizedBox(
              width: widget.size * 0.42,
              height: widget.size * 0.42,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.primary.withValues(alpha: 0.72),
                ),
              ),
            )
          : SizedBox(
              width: widget.size * 0.54,
              height: widget.size * 0.54,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    child: Container(
                      width: widget.size * 0.2,
                      height: widget.size * 0.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: widget.size * 0.36,
                      height: widget.size * 0.17,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(widget.size * 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
