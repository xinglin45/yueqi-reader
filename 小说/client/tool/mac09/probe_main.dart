import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:platform_services/platform_services.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/infrastructure/platform_storage_locations.dart';

/// The same application, with only the storage location injected for native QA.
/// No user documents, declaration state, or production database are modified.
final class ProbeLocations implements StorageLocationProvider {
  @override
  Future<AppStorageLocations> locations() async {
    final system = await const SystemStorageLocations().locations();
    return AppStorageLocations(
      support: p.join(system.support, 'mac09-probe'),
      cache: p.join(system.cache, 'mac09-probe'),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.open(ProbeLocations());
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: 'MAC-09 隔离检查',
        location: BannerLocation.topEnd,
        child: NovelApp(dependencies: dependencies),
      ),
    ),
  );
}
