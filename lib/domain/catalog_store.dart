import 'catalog.dart';

abstract interface class CatalogStore {
  Future<CatalogSnapshot?> loadCatalog(GameMode mode);
  Future<void> commitCatalog(CatalogSnapshot snapshot);
}
