import 'package:flutter/material.dart';

import '../widgets/activity_feed.dart';

/// The global Activity tab (spec §10): everything, newest first.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: const ActivityFeed(showGroupName: true),
    );
  }
}
