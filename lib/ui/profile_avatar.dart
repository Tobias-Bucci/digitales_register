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
import 'dart:math' as math;

import 'package:dr/middleware/middleware.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Who an avatar stands for: the [name] gives the initials, and [account], which
/// stays the same while the name is still being loaded, gives the colour.
@immutable
class ProfileIdentity {
  const ProfileIdentity({required this.name, required this.account});

  final String? name, account;

  @override
  bool operator ==(Object other) =>
      other is ProfileIdentity &&
      other.name == name &&
      other.account == account;

  @override
  int get hashCode => Object.hash(name, account);
}

final _letter = RegExp(r'\p{L}', unicode: true);

/// The first letter of [word] as a capital, or null if it has none.
String? _initialOf(String word) {
  for (final character in word.characters) {
    if (!_letter.hasMatch(character)) continue;
    final upper = character.toUpperCase();
    // A ß would become two letters.
    return upper.characters.length == 1 ? upper : character;
  }
  return null;
}

/// One or two initials of [name]: those of its first and last word. With a
/// single word such as a user name, its parts count (max.muster gives MM). Empty
/// if [name] holds no letter at all.
String profileInitials(String? name) {
  if (name == null) return '';
  List<String> initialsOf(Iterable<String> words) =>
      words.map(_initialOf).nonNulls.toList();
  var initials = initialsOf(name.trim().split(RegExp(r'\s+')));
  if (initials.length == 1) {
    final parts = initialsOf(name.trim().split(RegExp(r'[._\-]+')));
    if (parts.length > 1) initials = parts;
  }
  if (initials.isEmpty) return '';
  return initials.length == 1 ? initials.first : initials.first + initials.last;
}

/// The colours of an initials avatar: a calm tone of one of the accents, a touch
/// lighter at the top because the light of the glass comes from there.
@immutable
class ProfileAvatarColors {
  const ProfileAvatarColors({
    required this.top,
    required this.bottom,
    required this.foreground,
  });

  final Color top, bottom, foreground;

  static const _maxChroma = 30.0;
  static final _cache = <(String, Brightness), ProfileAvatarColors>{};

  /// The same for [account] on every start, unlike [String.hashCode].
  static int _hash(String account) {
    var hash = 0x811c9dc5;
    for (final unit in account.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  factory ProfileAvatarColors.of(ColorScheme scheme, String account) =>
      _cache.putIfAbsent((account, scheme.brightness), () {
        const accents = AppAccent.values;
        final accent = accents[_hash(account) % accents.length];
        final hct = Hct.fromInt(accent.seed.toARGB32());
        final tones = TonalPalette.of(
          hct.hue,
          math.min(hct.chroma, _maxChroma),
        );
        final dark = scheme.brightness == Brightness.dark;
        return ProfileAvatarColors(
          top: Color(tones.get(dark ? 34 : 91)),
          bottom: Color(tones.get(dark ? 30 : 88)),
          foreground: Color(tones.get(dark ? 92 : 20)),
        );
      });
}

/// The profile picture, or initials or a figure for as long as there is none to
/// show.
///
/// That fallback stands whenever the picture is missing, loading, cannot be
/// decoded or belongs to nobody yet, so the avatar is never just empty, and a
/// picture fades in on top of it. Without [identity] or a letter in its name, it
/// is the figure. The avatar lives for as long as the app in the navigation of
/// the new design, so it has to find its way to the picture by itself: it tries
/// again after a failure and whenever [profilePictureRetries] says that the
/// reason may be gone.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    this.identity,
    this.size = 44,
    this.showProgress = true,
  });

  static const pictureKey = Key('profile-avatar-picture');
  static const figureKey = Key('profile-avatar-figure');
  static const initialsKey = Key('profile-avatar-initials');

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
  final ProfileIdentity? identity;
  final double size;

  /// Whether a load shows as a spinner instead of the figure. Off in places that
  /// have to stay calm, such as the navigation bar.
  final bool showProgress;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar>
    with SingleTickerProviderStateMixin {
  /// The picture fades in over what stood there. Only the picture moves: if both
  /// faded, the page would shine through the middle of the fade.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  )..addStatusListener((status) {
      if (status.isCompleted && mounted) setState(() {});
    });

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
    _reveal.dispose();
    super.dispose();
  }

  /// Starts over for a new address. What was shown belonged to the old one, and
  /// that may have been another account.
  void _resolve() {
    final url = widget.imageUrl;
    final known = url == null || url.isEmpty;
    _picture = known ? null : cachedProfilePicture(url);
    _reveal.value = 1;
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
      if (_picture == null && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_reveal.forward(from: 0));
      }
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
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (picture == null || _reveal.isAnimating) _buildFallback(context),
          if (picture != null)
            FadeTransition(
              key: const ValueKey('profile-avatar-reveal'),
              opacity: _reveal,
              child: ClipOval(
                child: Image(
                  key: ProfileAvatar.pictureKey,
                  image: picture,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // The image cache may have let go of it in the meantime.
                  frameBuilder: (context, child, frame, synchronous) =>
                      frame == null && !synchronous
                          ? _buildFallback(context)
                          : child,
                  errorBuilder: (context, _, __) => _buildFallback(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final identity = widget.identity;
    final initials = profileInitials(identity?.name);
    final spinning = _isResolving && widget.showProgress;
    if (identity == null || initials.isEmpty || spinning) {
      return _buildFigure(context);
    }
    return _buildInitials(
      context,
      initials,
      identity.account ?? identity.name!,
    );
  }

  Widget _buildInitials(
    BuildContext context,
    String initials,
    String account,
  ) {
    final colors = ProfileAvatarColors.of(
      Theme.of(context).colorScheme,
      account,
    );
    final highContrast = MediaQuery.highContrastOf(context);
    return GlassEdge(
      key: ProfileAvatar.initialsKey,
      shape: const CircleBorder(),
      sheen: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.top, colors.bottom],
          ),
          border: highContrast ? Border.all(color: colors.foreground) : null,
        ),
        child: Center(
          // Who it is, a screen reader gets from the place around it.
          child: ExcludeSemantics(
            child: Text(
              initials,
              maxLines: 1,
              softWrap: false,
              // It has to fit the circle at any text size.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: colors.foreground,
                fontSize: widget.size * (initials.length > 1 ? 0.38 : 0.46),
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
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
