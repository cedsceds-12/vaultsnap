import 'package:flutter/material.dart';

/// [MaterialApp.navigatorKey] — pop to root (and dismiss modals) when vault locks.
final GlobalKey<NavigatorState> vaultRootNavigatorKey =
    GlobalKey<NavigatorState>();
