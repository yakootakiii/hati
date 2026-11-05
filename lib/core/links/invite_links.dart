import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/router.dart';

part 'invite_links.g.dart';

/// The invite token in a link Hati was opened with, or null if it is not an
/// invite (DECISIONS D-69). Two forms:
///
///   `https://hati-a1a23.web.app/join/TOKEN` — the shared link
///   `com.hati.hati://join/TOKEN` — the invite page's button
///
/// Auth callbacks (com.hati.hati://auth-callback) are not invites; Supabase
/// handles those itself.
String? inviteTokenFrom(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final String? token;
  if (uri.scheme == 'https' && uri.host == 'hati-a1a23.web.app') {
    token = segments.length == 2 && segments.first == 'join' ? segments[1] : null;
  } else if (uri.scheme == 'com.hati.hati' && uri.host == 'join') {
    token = segments.length == 1 ? segments.single : null;
  } else {
    token = null;
  }
  if (token == null || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
    return null;
  }
  return token;
}

/// Where links come from — a seam, so tests need no platform channel.
abstract interface class LinkSource {
  Future<Uri?> initial();
  Stream<Uri> get links;
}

class AppLinksSource implements LinkSource {
  final _appLinks = AppLinks();

  @override
  Future<Uri?> initial() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}

@Riverpod(keepAlive: true)
LinkSource linkSource(Ref ref) => AppLinksSource();

/// Sends invite links to the join screen — the one Hati opened with and any
/// that arrive while it runs. Signed out, the router stashes the invite and
/// resumes it after sign-in (spec §8.1).
@Riverpod(keepAlive: true)
class InviteLinkRouter extends _$InviteLinkRouter {
  @override
  void build() {
    final source = ref.watch(linkSourceProvider);
    final subscription = source.links.listen(_open, onError: (_) {});
    ref.onDispose(subscription.cancel);
    unawaited(
      source.initial().then((uri) {
        if (uri != null) _open(uri);
      }).catchError((Object error) {
        debugPrint('[links] no initial link: $error');
      }),
    );
  }

  void _open(Uri uri) {
    final token = inviteTokenFrom(uri);
    if (token == null) return;
    ref.read(routerProvider).go(Routes.joinToken(token));
  }
}
