import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'supabase_config.dart';

part 'supabase_providers.g.dart';

/// Whether this build has a Supabase project attached.
///
/// A provider rather than a direct [SupabaseConfig] read so that widget tests
/// can override it and exercise the real routing without a live project.
@Riverpod(keepAlive: true)
bool isBackendConfigured(Ref ref) => SupabaseConfig.isConfigured;
