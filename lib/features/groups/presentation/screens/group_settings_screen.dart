import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/images/attachment_storage.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/images/image_service.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';

/// Group settings (spec §10): rename, photo, archive.
class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Group settings')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load this group.',
          onRetry: () => ref.invalidate(myGroupsProvider),
        ),
        data: (all) {
          final group = all.where((g) => g.id == groupId).firstOrNull;
          if (group == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Group not found',
              message: "You're not a member of this group any more.",
            );
          }
          return _Settings(group: group);
        },
      ),
    );
  }
}

class _Settings extends ConsumerStatefulWidget {
  const _Settings({required this.group});

  final GroupSummary group;

  @override
  ConsumerState<_Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<_Settings> {
  late final TextEditingController _name = TextEditingController(
    text: widget.group.name,
  );
  PickedImage? _pendingPhoto;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    // Only owners and admins may change a group (spec §5.4). The screen is
    // read-only for everyone else rather than failing on save.
    final canEdit = group.canInvite;

    return ListView(
      padding: kPagePadding,
      children: [
        Center(
          child: _pendingPhoto != null
              ? PendingImageThumb(
                  bytes: _pendingPhoto!.bytes,
                  size: 120,
                  onRemove: () => setState(() => _pendingPhoto = null),
                )
              : _GroupPhoto(group: group),
        ),
        if (canEdit) ...[
          const SizedBox(height: kSpace),
          Center(
            child: TextButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                group.photoPath == null ? 'Add a photo' : 'Change photo',
              ),
            ),
          ),
        ],

        const SizedBox(height: kSpace * 3),
        TextField(
          controller: _name,
          enabled: canEdit,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),

        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: kSpace),
        ],

        if (canEdit)
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save changes'),
          )
        else
          Text(
            'Only an owner or admin can change these.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

        const Divider(height: kSpace * 5),
        SwitchListTile(
          value: group.isArchived,
          onChanged: canEdit ? (value) => _setArchived(value) : null,
          contentPadding: EdgeInsets.zero,
          title: const Text('Archived'),
          subtitle: const Text(
            'Moves it out of the way. Nobody is removed and no bills change.',
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    final source = await askImageSource(context);
    if (source == null || !mounted) return;

    final picked = await ref.read(imageServiceProvider).pick(source);
    if (picked == null || !mounted) return;

    setState(() => _pendingPhoto = picked);
  }

  Future<void> _save() async {
    final actions = ref.read(groupActionsProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });

    String? photoPath;
    if (_pendingPhoto != null) {
      final storage = ref.read(attachmentStorageProvider);
      photoPath = StoragePaths.groupPhoto(
        widget.group.id,
        storage.newFilename(),
      );
      try {
        await storage.upload(
          bucket: StorageBucket.groupPhotos,
          path: photoPath,
          image: _pendingPhoto!,
        );
      } on AttachmentFailure catch (failure) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Could not upload the photo: ${failure.message}';
        });
        return;
      }
    }

    final ok = await actions.updateGroup(
      groupId: widget.group.id,
      name: _name.text.trim(),
      photoPath: photoPath,
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      context.pop();
    } else {
      setState(() => _error = actions.lastError);
    }
  }

  Future<void> _setArchived(bool archived) async {
    final actions = ref.read(groupActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await actions.setArchived(
      groupId: widget.group.id,
      archived: archived,
    );
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'That did not work.')),
      );
    }
  }
}

class _GroupPhoto extends StatelessWidget {
  const _GroupPhoto({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = group.photoPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox.square(
        dimension: 120,
        child: path == null || path.isEmpty
            ? Container(
                color: theme.colorScheme.secondaryContainer,
                alignment: Alignment.center,
                child: Icon(
                  Icons.groups,
                  size: 48,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              )
            : AttachmentImage(
                bucket: StorageBucket.groupPhotos,
                path: path,
                width: 120,
                height: 120,
                semanticLabel: '${group.name} photo',
              ),
      ),
    );
  }
}
