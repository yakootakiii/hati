import 'package:freezed_annotation/freezed_annotation.dart';

part 'comment.freezed.dart';
part 'comment.g.dart';

/// A comment on a bill (spec §10).
@freezed
abstract class Comment with _$Comment {
  const factory Comment({
    required String id,
    required String billId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    String? authorName,
    String? authorAvatarPath,
    DateTime? editedAt,
    DateTime? deletedAt,
  }) = _Comment;

  const Comment._();

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);

  /// Deleted comments stay in place as a tombstone, so a thread does not
  /// silently lose its shape.
  bool get isDeleted => deletedAt != null;

  bool get wasEdited => editedAt != null && !isDeleted;

  String get author => authorName ?? 'Someone';

  String get displayBody => isDeleted ? 'Comment deleted' : body;
}
