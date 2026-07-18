import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/time_service.dart';
import '../../../core/utils/app_logger.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Wipe all local state tied to a user session.
  /// Called at every auth transition (signOut, signIn, signUp)
  /// to guarantee no cross-user data leak.
  Future<void> _wipeLocalState() async {
    try {
      await DatabaseHelper().deleteAllData();
    } catch (e, st) {
      AppLogger.error('AuthService', 'wipeLocalState: SQLite wipe failed',
          error: e, stackTrace: st);
      // Continue — partial wipe is better than throwing.
    }
    try {
      await TimeService().clearCache();
    } catch (e, st) {
      AppLogger.error('AuthService', 'wipeLocalState: TimeService cache clear failed',
          error: e, stackTrace: st);
    }
  }

  // Sign up with email + password (sends OTP for email confirmation)
  Future<Map<String, dynamic>> signUp(String email, String password) async {
    await _wipeLocalState();
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return {'success': true, 'message': 'auth_otp_sent'.tr(namedArgs: {'email': email})};
      } else {
        return {'success': false, 'message': 'auth_signup_failed'.tr()};
      }
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'auth_something_wrong'.tr()};
    }
  }

  /// Resend the signup confirmation OTP to a previously-registered
  /// (but unconfirmed) email. Does NOT create a new account or
  /// require a password.
  Future<Map<String, dynamic>> resendSignupOtp(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      return {'success': true, 'message': 'auth_otp_resent'.tr()};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'auth_something_wrong'.tr()};
    }
  }

  // Verify OTP after sign up
  Future<Map<String, dynamic>> verifySignUpOtp(String email, String otp) async {
    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );

      if (response.session != null) {
        return {'success': true, 'message': 'auth_account_verified'.tr()};
      } else {
        return {'success': false, 'message': 'auth_invalid_code'.tr()};
      }
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'auth_something_wrong'.tr()};
    }
  }

  // Login with email + password (no OTP needed)
  Future<Map<String, dynamic>> login(String email, String password) async {
    await _wipeLocalState();
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session != null) {
        return {'success': true, 'message': 'login_success'.tr()};
      } else {
        return {'success': false, 'message': 'auth_login_failed'.tr()};
      }
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'auth_something_wrong'.tr()};
    }
  }

  // Send password reset email
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return {'success': true, 'message': 'auth_reset_link_sent'.tr(namedArgs: {'email': email})};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'auth_something_wrong'.tr()};
    }
  }

  // Save shop profile to Supabase
  Future<Map<String, dynamic>> saveProfile({
    required String ownerName,
    required String phone,
    required String shopName,
    required String address,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'auth_not_logged_in'.tr()};
      }

      final saved = await SyncService().saveShopProfile({
        'id': user.id,
        'owner_name': ownerName,
        'phone': phone,
        'shop_name': shopName,
        'address': address,
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (!saved) {
        return {'success': false, 'message': 'auth_profile_save_failed'.tr()};
      }

      return {'success': true, 'message': 'auth_profile_saved'.tr()};
    } catch (e) {
      return {'success': false, 'message': 'auth_profile_save_failed'.tr()};
    }
  }

  // Check if user is logged in
  bool get isLoggedIn => _client.auth.currentSession != null;

  // Get current user
  User? get currentUser => _client.auth.currentUser;

  // Sign out
  Future<void> signOut() async {
    await _wipeLocalState();
    await _client.auth.signOut();
  }
}