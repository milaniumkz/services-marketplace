import 'package:flutter/material.dart';
import 'design_widgets.dart';

class NavigationState {
  final String route;
  final bool executor, enabled;
  final int messages, notifications;
  final ValueChanged<String> onSelect;
  const NavigationState(
      {required this.route,
      required this.executor,
      required this.enabled,
      required this.messages,
      required this.notifications,
      required this.onSelect});
  bool sameAs(NavigationState? other) =>
      other != null &&
      route == other.route &&
      executor == other.executor &&
      enabled == other.enabled &&
      messages == other.messages &&
      notifications == other.notifications;
}

class NavigationFrame extends StatelessWidget {
  final NavigationState? navigation;
  final Widget child;
  const NavigationFrame(
      {super.key, required this.navigation, required this.child});
  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    if (nav == null) return child;
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Column(children: [
              Expanded(child: child),
              Material(
                  color: Colors.white,
                  child: JobaNavigation(
                      route: nav.route,
                      executor: nav.executor,
                      enabled: nav.enabled,
                      messageCount: nav.messages,
                      notificationCount: nav.notifications,
                      onSelect: nav.onSelect))
            ])));
  }
}
