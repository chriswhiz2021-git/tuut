// Tuut – Hauptbildschirm: Kontakte, Wählfeld, Anrufe, Guthaben.
// Breite Fenster (PC): Navigation links. Schmale (Handy): Navigation unten.
import 'package:flutter/material.dart';
import '../matrix_service.dart';
import 'balance_screen.dart';
import 'call_log_screen.dart';
import 'contacts_screen.dart';
import 'dialpad_screen.dart';

class HomeShell extends StatefulWidget {
  final MatrixService service;
  const HomeShell({super.key, required this.service});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ValueNotifier<int> _tab = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  static const _items = [
    (Icons.people_outline, Icons.people, 'Kontakte'),
    (Icons.dialpad_outlined, Icons.dialpad, 'Wählfeld'),
    (Icons.history, Icons.history, 'Anrufe'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Guthaben'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return ValueListenableBuilder<int>(
      valueListenable: _tab,
      builder: (context, index, _) {
        final body = IndexedStack(
          index: index,
          children: [
            ContactsScreen(service: s),
            DialpadScreen(service: s, tab: _tab, myIndex: 1, onOpenBalance: () => _tab.value = 3),
            CallLogScreen(service: s, tab: _tab, myIndex: 2),
            BalanceScreen(service: s, tab: _tab, myIndex: 3),
          ],
        );
        return LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: (i) => _tab.value = i,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final it in _items)
                        NavigationRailDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            );
          }
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _tab.value = i,
              destinations: [
                for (final it in _items)
                  NavigationDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3),
              ],
            ),
          );
        });
      },
    );
  }
}
