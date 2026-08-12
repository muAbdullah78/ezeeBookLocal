/// Application version. Keep in sync with pubspec.yaml `version:`.
/// When bumping pubspec version, update this value too.
const String kAppVersion = '2.2.1';

/// Fixed primary-key used for the single local shop profile row.
///
/// The app is now fully offline with exactly one shop per device, so there
/// is no per-user id anymore. Every read/write of the shop profile uses this
/// constant id.
const String kLocalShopId = 'local_shop';

/// Public-facing URLs for legal pages. Hosted on GitHub Pages.
const String kPrivacyPolicyUrl =
    'https://muabdullah78.github.io/ezeebook/privacy-policy.html';
const String kTermsOfServiceUrl =
    'https://muabdullah78.github.io/ezeebook/terms-of-service.html';

/// Support contact for users encountering issues.
const String kSupportEmail = 'muabdullah9987@gmail.com';
const String kSupportPhone = '03331663011';
