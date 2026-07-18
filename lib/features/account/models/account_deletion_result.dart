/// Result of an account deletion attempt.
///
/// [success] is true only when the Edge Function returned 200, local data
/// was cleared and the Supabase session was signed out. On any failure,
/// [success] is false and [errorMessage] carries a user-friendly, localized
/// message the UI can surface directly.
class AccountDeletionResult {
  final bool success;
  final String? errorMessage;

  AccountDeletionResult.success()
      : success = true,
        errorMessage = null;

  AccountDeletionResult.failure(this.errorMessage) : success = false;
}
