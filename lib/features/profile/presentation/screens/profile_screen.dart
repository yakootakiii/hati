import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/images/attachment_storage.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/images/image_service.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/profile_repository.dart';

/// Profile and settings (spec §10).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Who you are, then what you can change — the identity is
                // the page, not a card on it.
                InkWell(
                  borderRadius: BorderRadius.circular(kRadiusLg),
                  onTap: () => _editProfile(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: kSpace * 2,
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          displayName:
                              profile.asData?.value?.displayName ?? '',
                          avatarPath: profile.asData?.value?.avatarPath,
                          radius: 30,
                        ),
                        const SizedBox(width: kSpace * 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.asData?.value?.displayName ?? 'You',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'How your barkada sees you',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit profile',
                          onPressed: () => _editProfile(context, ref),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                ),

                const SectionHeader('Getting paid'),
                ListGroup(
                  dividerIndent: 56,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.qr_code_2),
                      title: const Text('Payment methods'),
                      subtitle: const Text('Your wallet QR codes and numbers'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.paymentMethods),
                    ),
                  ],
                ),

                const SectionHeader('Preferences'),
                ListGroup(
                  dividerIndent: 56,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: const Text('What Hati tells you about'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.notificationPrefs),
                    ),
                    ListTile(
                      leading: const Icon(Icons.contrast),
                      title: const Text('Appearance'),
                      subtitle: const Text('Light, dark, or match your phone'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.appearance),
                    ),
                  ],
                ),

                const SectionHeader('Legal'),
                ListGroup(
                  dividerIndent: 56,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Terms and Conditions'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.terms),
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Notice'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.privacy),
                    ),
                  ],
                ),

                const SizedBox(height: kSpace * 3),
                ListGroup(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Log out',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onTap: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                    ),
                  ],
                ),

                const SizedBox(height: kSpace * 3),
                Center(
                  child: TextButton(
                    onPressed: () => context.push(Routes.deleteAccount),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('Delete account'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EditProfileSheet(),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet();

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController? _name;
  PickedImage? _pendingAvatar;
  String? _error;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider).asData?.value;
    final state = ref.watch(profileActionsProvider);
    _name ??= TextEditingController(text: profile?.displayName ?? '');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: kSpace * 3),

                Center(
                  child: _pendingAvatar != null
                      ? PendingImageThumb(
                          bytes: _pendingAvatar!.bytes,
                          size: 96,
                          onRemove: () => setState(() => _pendingAvatar = null),
                        )
                      : UserAvatar(
                          displayName: profile?.displayName ?? '',
                          avatarPath: profile?.avatarPath,
                          radius: 48,
                        ),
                ),
                const SizedBox(height: kSpace * 2),
                Center(
                  child: TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      profile?.hasAvatar ?? false
                          ? 'Change photo'
                          : 'Add a photo',
                    ),
                  ),
                ),

                const SizedBox(height: kSpace * 2),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: kSpace),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],

                const SizedBox(height: kSpace * 2),
                FilledButton(
                  onPressed: state.isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final source = await askImageSource(context);
    if (source == null || !mounted) return;

    final picked = await ref.read(imageServiceProvider).pick(source);
    if (picked == null || !mounted) return;

    setState(() => _pendingAvatar = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final actions = ref.read(profileActionsProvider.notifier);
    String? avatarPath;

    // The image goes up first: the profile row stores its path, so the object
    // has to exist before the row points at it.
    if (_pendingAvatar != null) {
      final storage = ref.read(attachmentStorageProvider);
      final userId = ref.read(sessionStateProvider).userId;
      if (userId == null) return;

      avatarPath = StoragePaths.avatar(userId, storage.newFilename());
      try {
        await storage.upload(
          bucket: StorageBucket.avatars,
          path: avatarPath,
          image: _pendingAvatar!,
        );
      } on AttachmentFailure catch (failure) {
        if (!mounted) return;
        setState(() => _error = 'Could not upload the photo: ${failure.message}');
        return;
      }
    }

    final ok = await actions.save(
      displayName: _name!.text.trim(),
      avatarPath: avatarPath,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = actions.lastError);
    }
  }
}
