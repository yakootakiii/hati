import 'dart:async';

import 'package:hati/core/links/invite_links.dart';

/// A [LinkSource] a test drives by hand.
class FakeLinkSource implements LinkSource {
  FakeLinkSource({this.launchLink});

  /// The link the app was "opened with".
  Uri? launchLink;
  final _links = StreamController<Uri>.broadcast();

  void open(String link) => _links.add(Uri.parse(link));

  @override
  Future<Uri?> initial() async => launchLink;

  @override
  Stream<Uri> get links => _links.stream;
}
