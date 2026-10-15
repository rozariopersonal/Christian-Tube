import 'database_init_stub.dart'
    if (dart.library.io) 'database_init_ffi.dart';

/// Initializes SQLite database factories on platforms where sqflite requires FFI
/// (Windows, Linux, macOS). Safe no-op on Android, iOS, and Web.
void initPlatformDatabases() => initPlatformDatabasesImpl();
