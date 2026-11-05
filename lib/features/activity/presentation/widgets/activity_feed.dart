import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/data/auth_repository.dart';
import '../../domain/activity_event.dart';
import '../activity_controller.dart';

/// A feed of activity, for one group or across all of them (spec §10).
class ActivityFeed extends ConsumerStatefulWidget {
  const ActivityFeed({this.groupId, this.showGroupName = false, super.key});

  /// Null for the merged feed.
  final String? groupId;

  /// The merged feed says which group each entry belongs to.
  final bool showGroupName;

  @override
  ConsumerState<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends ConsumerState<ActivityFeed> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref
          .read(activityPagerProvider(groupId: widget.groupId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(activityPagerProvider(groupId: widget.groupId));
    final myId = ref.watch(sessionStateProvider).userId;

    return events.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorRetry(
        message: 'Could not load the activity.',
        onRetry: () =>
            ref.invalidate(activityPagerProvider(groupId: widget.groupId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'Nothing yet',
            message: 'Bills, payments and comments will show up here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(activityPagerProvider(groupId: widget.groupId));
            await ref
                .read(activityPagerProvider(groupId: widget.groupId).future);
          },
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: kSpace * 2),
            itemBuilder: (_, index) => _EventRow(
              event: list[index],
              actorIsMe: list[index].actorId != null &&
                  list[index].actorId == myId,
              showGroupName: widget.showGroupName,
            ),
          ),
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.actorIsMe,
    required this.showGroupName,
  });

  final ActivityEvent event;
  final bool actorIsMe;
  final bool showGroupName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = event.route;

    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpace),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: kSpace * 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.describe(actorIsMe: actorIsMe),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: kSpace / 2),
                  Text(
                    [
                      if (showGroupName) event.groupName,
                      _relative(event.createdAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _icon => switch (event.kind) {
        ActivityType.groupCreated => Icons.group_add_outlined,
        ActivityType.memberJoined => Icons.person_add_alt,
        ActivityType.memberLeft || ActivityType.memberRemoved =>
          Icons.person_remove_outlined,
        ActivityType.billCreated || ActivityType.recurringGenerated =>
          Icons.receipt_long_outlined,
        ActivityType.billEdited => Icons.edit_outlined,
        ActivityType.billVoided => Icons.block,
        ActivityType.paymentMarked => Icons.payments_outlined,
        ActivityType.paymentConfirmed => Icons.check_circle_outline,
        ActivityType.paymentRejected => Icons.error_outline,
        ActivityType.billSettled => Icons.celebration_outlined,
        ActivityType.commentAdded => Icons.chat_bubble_outline,
        ActivityType.recurringCreated => Icons.repeat,
        ActivityType.unknown => Icons.circle_outlined,
      };

  static String _relative(DateTime when) {
    final local = when.toLocal();
    final difference = DateTime.now().difference(local);

    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return DateFormat.yMMMd('en_PH').format(local);
  }
}
