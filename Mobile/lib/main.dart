import 'package:flutter/material.dart';

import 'app.dart';
import 'services/offline_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AgroFusionApp(offlineStore: OfflineStore()));
}
