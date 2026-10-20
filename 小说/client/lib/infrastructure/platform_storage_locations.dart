import 'package:path_provider/path_provider.dart';
import 'package:platform_services/platform_services.dart';

/// The sole path_provider boundary. No inferred home or development paths.
final class SystemStorageLocations implements StorageLocationProvider {
  const SystemStorageLocations();
  @override
  Future<AppStorageLocations> locations() async => AppStorageLocations(
    support: (await getApplicationSupportDirectory()).path,
    cache: (await getApplicationCacheDirectory()).path,
  );
}
