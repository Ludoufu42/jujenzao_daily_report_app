/// Fallback for compile targets that are neither dart:io-capable (desktop/
/// mobile) nor dart:html-capable (web) — should never actually be selected
/// by the conditional import in database_helper.dart, but keeps the
/// conditional-import trio complete.
void ensurePlatformDatabaseFactory() {}
