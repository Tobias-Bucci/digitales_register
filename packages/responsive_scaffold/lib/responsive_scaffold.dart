library responsive_scaffold;

import 'package:flutter/material.dart' hide SizeTransition;
import 'package:flutter_portal/flutter_portal.dart';
import 'package:responsive_scaffold/size_transition.dart';

const tabletLayoutBreakpoint = 720.0;
const drawerWidth = 304.0;

class _PopObserver extends NavigatorObserver {
  final VoidCallback onReturnedToRoot;
  final void Function(Object? routeArguments) onReturnedTo;

  _PopObserver(this.onReturnedToRoot, this.onReturnedTo);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst == true) {
      onReturnedToRoot();
    } else if (previousRoute != null) {
      onReturnedTo(previousRoute.settings.arguments);
    }
  }
}

/// Replaces the drawer and sidebar of a [ResponsiveScaffold] with persistent
/// navigation: a bar floating above the content on phones and a rail next to
/// it on tablets and desktop windows.
class ResponsiveNavigation<T> {
  const ResponsiveNavigation({
    required this.barBuilder,
    required this.railBuilder,
    required this.barExtent,
    required this.isTopLevel,
    this.keepsRouteBelow,
  });

  /// Builds the floating bar. It is aligned to the bottom of the scaffold and
  /// has to respect the bottom safe area itself.
  final Widget Function(BuildContext context, T currentSelected) barBuilder;

  /// Builds the rail shown to the left of the content in tablet mode.
  final Widget Function(BuildContext context, T currentSelected) railBuilder;

  /// How far the bar reaches above the bottom safe area. Pages receive this as
  /// additional bottom padding, so scroll views end above the bar.
  final double barExtent;

  /// Whether a page is a destination of its own. Those pages have no back
  /// button; every other page gets one.
  final bool Function(T page) isTopLevel;

  /// Whether selecting `next` from `current` keeps `current` below it, so that
  /// going back returns to `current` instead of the home page.
  final bool Function(T current, T next)? keepsRouteBelow;
}

/// A widget that provides a responsive scaffold implementation.
///
/// Concepts:
/// - There is one home page, and zero or more sub-pages.
/// - On mobile, the drawer can be opened by tapping on the hamburger menu on
///   the home page, where a sub-page can be selected to navigate to. The drag
///   area to open the drawer is increased to the whole screen to make single-
///   handed navigation easier. Navigating back is possible by tapping the back
///   button in the AppBar of each sub-page. The home page is not shown in the drawer.
/// - On tablets, the drawer is always expanded as a sidebar. Sub-pages and the
///   home page are listed in the sidebar. After navigating to a sub-page, it is
///   possible to navigate back to the main page by selecting it in the sidebar.
///
/// Usage:
/// Replace the scaffold on the home page with this widget. This widget is
/// generic over the id associated to each page. To select a sub page, i.e. make
/// this widget push it to its internal navigator, either use the
/// [WidgetSelectedCallback] passed to the [drawerBuilder], or obtain the
/// enclosing instance of the [ResponsiveScaffoldState] by calling
/// [ResponsiveScaffold.of(context)] and call
/// [ResponsiveScaffoldState.selectContentWidget]. Similarly, to select the home
///  page, either call the callback passed to [drawerBuilder] or
/// [ResponsiveScaffoldState.goHome].
/// Make sure to handle back presses correctly! See the example for an example.
class ResponsiveScaffold<T> extends StatefulWidget {
  /// Similar to [Scaffold.body].
  /// Specifies the body of the home page.
  final Widget homeBody;

  /// Similar to [Scaffold.appBar].
  /// Specifies the appBar of the home page.
  final PreferredSizeWidget homeAppBar;

  /// Similar to [Scaffold.floatingActionButton].
  /// Specifies the floatingActionButton of the home page.
  final Widget? homeFloatingActionButton;

  /// The id of the home page
  final T homeId;

  /// [DrawerBuilder] callback.
  final DrawerBuilder<T> drawerBuilder;

  /// The navigator key that will be used for the internal navigator.
  /// As back events will be fired to the root navigator, you have to intercept
  /// them and pass them to this navigator manually.
  final GlobalKey<NavigatorState> navKey;

  final void Function(T newSelectedRoute)? onRouteChanged;

  /// Persistent navigation that replaces the drawer and sidebar; null keeps
  /// them. [drawerBuilder] is not used while this is set.
  final ResponsiveNavigation<T>? navigation;

  /// Lets the body of the home page scroll underneath [homeAppBar].
  final bool extendHomeBodyBehindAppBar;

  const ResponsiveScaffold({
    Key? key,
    required this.homeBody,
    required this.drawerBuilder,
    required this.homeId,
    required this.navKey,
    required this.homeAppBar,
    this.homeFloatingActionButton,
    this.onRouteChanged,
    this.navigation,
    this.extendHomeBodyBehindAppBar = false,
  }) : super(key: key);

  @override
  ResponsiveScaffoldState<T> createState() => ResponsiveScaffoldState<T>();

  ResponsiveScaffoldState<T>? of(BuildContext context) {
    return context.findAncestorStateOfType<ResponsiveScaffoldState<T>>();
  }
}

class ResponsiveScaffoldState<T> extends State<ResponsiveScaffold<T>>
    with SingleTickerProviderStateMixin {
  late final GlobalKey<NavigatorState> navigatorKey;

  late final AnimationController _drawerAnimationController;

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();
  late bool tabletMode;
  // This is required in order not to show an opening animation
  // right when the app is opened
  bool isInitialized = false;
  bool? _previousTabletMode;
  // The route kept below a page by [ResponsiveNavigation.keepsRouteBelow].
  Route<dynamic>? _routeKeptBelow;
  late final ValueNotifier<T> _currentSelected;
  T get currentSelected => _currentSelected.value;
  set currentSelected(T v) {
    _currentSelected.value = v;
  }

  @override
  void initState() {
    _currentSelected = ValueNotifier(widget.homeId)
      ..addListener(
        () {
          widget.onRouteChanged?.call(currentSelected);
        },
      );
    navigatorKey = widget.navKey;
    _drawerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    super.initState();
  }

  void closeDrawerIfOpen() {
    if (scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(scaffoldKey.currentContext!).pop();
    }
  }

  /// Pushes [content] to the body of the scaffold, associating [data] with it.
  void selectContentWidget(Widget content, T data) {
    closeDrawerIfOpen();
    final navigation = widget.navigation;
    final route = tabletMode || navigation != null
        ? PageRouteBuilder(
            settings: RouteSettings(arguments: data),
            pageBuilder: (_, animation, secondaryAnimation) => FadeTransition(
              opacity: animation,
              child: content,
            ),
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 250),
          )
        : MaterialPageRoute(
            settings: RouteSettings(arguments: data),
            builder: (context) => content,
          );
    // Make sure that there are no other routes pushed on our navigator
    final navigator = navigatorKey.currentState!;
    navigator.popUntil((route) => route.settings.arguments == currentSelected);
    final keepCurrent =
        navigation?.keepsRouteBelow?.call(currentSelected, data) ?? false;
    final keptBelow = _routeKeptBelow;
    if (!keepCurrent &&
        keptBelow != null &&
        keptBelow.isActive &&
        !keptBelow.isCurrent) {
      navigator.removeRoute(keptBelow);
    }
    if (keepCurrent) {
      // popUntil is the only way to read the current route.
      navigator.popUntil((route) {
        _routeKeptBelow = route;
        return true;
      });
      navigator.push(route);
    } else if (currentSelected == widget.homeId) {
      navigator.push(route);
    } else {
      navigator.pushReplacement(route);
    }
    setState(() {
      currentSelected = data;
    });
  }

  /// Pops all routes and resets the body of this scaffold to [widget.homeBody].
  /// [currentSelected] will be accordingly set to [widget.homeId].
  void goHome() {
    navigatorKey.currentState!.popUntil((route) => route.isFirst);
    _wentHome();
  }

  void _wentHome() {
    setState(() {
      currentSelected = widget.homeId;
    });
  }

  void _returnedTo(Object? routeArguments) {
    if (routeArguments is T && routeArguments != currentSelected) {
      setState(() {
        currentSelected = routeArguments;
      });
    }
  }

  @override
  void dispose() {
    _drawerAnimationController.dispose();
    _currentSelected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Portal(
      child: LayoutBuilder(
        builder: (context, constraints) {
          tabletMode = constraints.maxWidth >= tabletLayoutBreakpoint;
          if (tabletMode != _previousTabletMode) {
            if (tabletMode) {
              if (isInitialized) {
                if (_drawerAnimationController.value != 1) {
                  _drawerAnimationController.fling();
                }
              } else {
                _drawerAnimationController.value = 1;
              }
            } else if (_drawerAnimationController.value != 0) {
              _drawerAnimationController.fling(velocity: -1);
            }
          }
          _previousTabletMode = tabletMode;
          isInitialized = true;
          final navigation = widget.navigation;
          final body = _Body<T>(
            navKey: navigatorKey,
            navObserver: _PopObserver(_wentHome, _returnedTo),
            homeId: widget.homeId,
          );
          return _InheritedTabletMode(
            tabletMode: tabletMode,
            child: _InheritedHomePage(
              fab: widget.homeFloatingActionButton,
              scaffoldKey: scaffoldKey,
              body: widget.homeBody,
              appBar: widget.homeAppBar,
              extendBodyBehindAppBar: widget.extendHomeBodyBehindAppBar,
              drawer: !tabletMode && navigation == null
                  ? widget.drawerBuilder(
                      selectContentWidget,
                      goHome,
                      currentSelected,
                      false,
                    )
                  : null,
              child: Material(
                child: navigation != null
                    ? _buildWithNavigation(context, navigation, body)
                    : Row(
                        children: [
                          SizeTransition(
                            axis: Axis.horizontal,
                            sizeFactor: _drawerAnimationController,
                            axisAlignment: 1,
                            child: _Drawer(
                              drawerAnimationController:
                                  _drawerAnimationController,
                              child: widget.drawerBuilder(
                                selectContentWidget,
                                goHome,
                                currentSelected,
                                true,
                              ),
                            ),
                          ),
                          Expanded(child: body),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWithNavigation(
    BuildContext context,
    ResponsiveNavigation<T> navigation,
    Widget body,
  ) {
    final media = MediaQuery.of(context);
    // The keyboard covers the bar, so nothing has to stay clear of it then.
    final showBar = !tabletMode && media.viewInsets.bottom == 0;
    final inset = showBar ? navigation.barExtent : 0.0;
    return Row(
      children: [
        if (tabletMode) navigation.railBuilder(context, currentSelected),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: media.copyWith(
                    padding: media.padding
                        .copyWith(bottom: media.padding.bottom + inset),
                    viewPadding: media.viewPadding
                        .copyWith(bottom: media.viewPadding.bottom + inset),
                  ),
                  child: _InheritedNavigation(
                    bottomInset: inset,
                    isTopLevelRoute: (arguments) =>
                        arguments is T && navigation.isTopLevel(arguments),
                    child: body,
                  ),
                ),
              ),
              if (showBar)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: navigation.barBuilder(context, currentSelected),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Describes the [ResponsiveNavigation] around a page.
class _InheritedNavigation extends InheritedWidget {
  final double bottomInset;
  final bool Function(Object? routeArguments) isTopLevelRoute;

  const _InheritedNavigation({
    required this.bottomInset,
    required this.isTopLevelRoute,
    required Widget child,
  }) : super(child: child);

  static _InheritedNavigation? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_InheritedNavigation>();
  }

  @override
  bool updateShouldNotify(_InheritedNavigation oldWidget) {
    return oldWidget.bottomInset != bottomInset;
  }
}

/// What a page has to know about the navigation around it.
abstract final class ResponsiveNavigationScope {
  /// Whether [context] is below a [ResponsiveNavigation].
  static bool isActive(BuildContext context) =>
      _InheritedNavigation.of(context) != null;

  /// The height of the floating bar above the bottom safe area, or 0 without
  /// one. [MediaQuery] already includes it: scroll views without an explicit
  /// padding need nothing else, but an explicit padding has to add this.
  static double bottomInsetOf(BuildContext context) =>
      _InheritedNavigation.of(context)?.bottomInset ?? 0;

  /// For [Scaffold.bottomNavigationBar] of a page whose body does not scroll
  /// as a whole: keeps the body clear of the floating bar, or null without one.
  static Widget? spacerOf(BuildContext context) => bottomInsetOf(context) > 0
      ? SizedBox(height: MediaQuery.paddingOf(context).bottom)
      : null;
}

class _Drawer extends StatefulWidget {
  const _Drawer({
    Key? key,
    required AnimationController drawerAnimationController,
    required this.child,
  })  : _drawerAnimationController = drawerAnimationController,
        super(key: key);

  final AnimationController _drawerAnimationController;
  final Widget child;

  @override
  __DrawerState createState() => __DrawerState();
}

class __DrawerState extends State<_Drawer> {
  late bool visible;
  @override
  void initState() {
    widget._drawerAnimationController.addStatusListener((status) {
      final shouldBeVisible = status != AnimationStatus.dismissed;
      if (shouldBeVisible != visible && mounted) {
        setState(() {
          visible = shouldBeVisible;
        });
      }
    });
    visible =
        widget._drawerAnimationController.status != AnimationStatus.dismissed;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PortalEntry(
      visible: visible,
      portalAnchor: Alignment.topLeft,
      childAnchor: Alignment.topRight,
      // The following is a hacky way to draw a shadow divider
      portal: Stack(
        children: [
          Positioned(
            left: 0,
            top: -4,
            bottom: -4,
            child: ClipRect(
              child: Container(
                width: 5,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(-7, 0),
                      blurRadius: 4,
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

class _InheritedTabletMode extends InheritedWidget {
  final bool tabletMode;

  const _InheritedTabletMode({required this.tabletMode, required Widget child})
      : super(child: child);

  static _InheritedTabletMode? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_InheritedTabletMode>();
  }

  @override
  bool updateShouldNotify(_InheritedTabletMode oldWidget) {
    return oldWidget.tabletMode != tabletMode;
  }
}

class _InheritedHomePage extends InheritedWidget {
  final Widget body;
  final Widget? drawer;
  final PreferredSizeWidget appBar;
  final Widget? fab;
  final Key scaffoldKey;
  final bool extendBodyBehindAppBar;

  const _InheritedHomePage({
    required this.body,
    required Widget child,
    required this.appBar,
    required this.drawer,
    required this.scaffoldKey,
    required this.extendBodyBehindAppBar,
    this.fab,
  }) : super(child: child);

  static _InheritedHomePage? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_InheritedHomePage>();
  }

  @override
  bool updateShouldNotify(_InheritedHomePage oldWidget) {
    // Comparing the widgets this class holds is not meaningful because they'd
    // have to be the exact same objects to compare equal.
    return true;
  }
}

class _Body<T> extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final NavigatorObserver navObserver;
  final T homeId;

  const _Body(
      {Key? key,
      required this.navKey,
      required this.navObserver,
      required this.homeId})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Navigator(
        observers: [navObserver],
        key: navKey,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case "/":
              return MaterialPageRoute(
                settings: RouteSettings(arguments: homeId),
                builder: (context) {
                  return _HomePage();
                },
              );
          }
          return null;
        },
      ),
    );
  }
}

typedef WidgetSelectedCallback<T> = void Function(Widget content, T data);
typedef DrawerBuilder<T> = Widget Function(
  WidgetSelectedCallback<T>,
  VoidCallback goHome,
  T currentSelected,
  bool tabletMode,
);

/// An Appbar that will not show a back button if not appropriate.
///
/// The back button will not be shown if we are in tablet mode. Below a
/// [ResponsiveNavigation] it is shown on every page that is not a destination
/// of its own, whatever the width of the window.
class ResponsiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const ResponsiveAppBar(
      {Key? key, required this.title, this.actions, this.leading, this.bottom})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final tabletMode = _InheritedTabletMode.of(context)?.tabletMode ?? false;
    final navigation = _InheritedNavigation.of(context);
    final showBack = navigation == null
        ? !tabletMode
        : !navigation
            .isTopLevelRoute(ModalRoute.settingsOf(context)?.arguments);
    return AppBar(
      actions: actions,
      leading: tabletMode ? null : leading,
      title: title,
      automaticallyImplyLeading: showBack,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));
}

class _HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final widgets = _InheritedHomePage.of(context)!;
    return Scaffold(
      appBar: widgets.appBar,
      drawer: widgets.drawer,
      body: widgets.body,
      key: widgets.scaffoldKey,
      floatingActionButton: widgets.fab,
      drawerEdgeDragWidth: double.infinity,
      extendBodyBehindAppBar: widgets.extendBodyBehindAppBar,
    );
  }
}
