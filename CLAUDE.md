# EzeeBook - Tailor Shop Management App

## Project Overview
EzeeBook is an Android app for Pakistani tailors (darzi) to manage their shops digitally. It replaces paper registers with digital customer tracking, order management, and measurement recording. The app is bilingual (English + Urdu) and works offline-first with cloud backup.

## Target User
- Pakistani tailors who run small shops
- Low-to-medium tech literacy
- Use Android phones (not iOS)
- Need offline functionality (internet is unreliable)
- Speak Urdu primarily, some English

## Tech Stack
- **Framework:** Flutter (Android only, ignore iOS)
- **Language:** Dart
- **Local Database:** sqflite (SQLite) - for offline-first data
- **Cloud Backend:** Supabase (PostgreSQL) - for cloud backup & auth
- **State Management:** Riverpod (not yet implemented, using StatefulWidget for now)
- **Authentication:** Supabase Auth (email + password signup with OTP confirmation, email + password login)
- **Localization:** easy_localization with JSON files (lib/l10n/en.json, lib/l10n/ur.json)
- **Navigation:** Manual Navigator.push (go_router added but not used yet)
- **Fonts:** Noto Nastaliq Urdu for Urdu text
- **Testing:** Windows desktop for daily dev, real Android phone for checkpoints

## Android Build Configuration

- `minSdk = 26` (Android 8.0)
- `targetSdk = 35` (Android 15) — required by Play Store policy for new apps
- `compileSdk = 36` (Android 16) — newer than targetSdk; intentional, build works
- `applicationId = com.usconnect.ezeebook`
- `namespace = com.usconnect.ezeebook`

## Project Location
`C:\dev\ezeebook\`

## Architecture & Folder Structure
```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart          # All color definitions
│   │   ├── app_text_styles.dart     # Text style definitions
│   │   └── supabase_config.dart     # Supabase URL and anon key (NEVER commit real keys)
│   ├── theme/
│   │   └── app_theme.dart           # Material 3 theme configuration
│   ├── database/
│   │   ├── database_helper.dart     # SQLite local database operations
│   │   └── sync_service.dart        # Dual save: local SQLite + Supabase cloud
│   └── utils/
│       └── pdf_generator.dart       # PDF generation for order receipts
├── features/
│   ├── auth/
│   │   ├── screens/
│   │   │   ├── consent_screen.dart             # First screen, data consent + T&C
│   │   │   ├── login_screen.dart              # Email + password login
│   │   │   ├── signup_screen.dart             # Full signup with OTP
│   │   │   ├── otp_screen.dart                # 6-digit OTP verification
│   │   │   └── forgot_password_screen.dart    # Password reset via email
│   │   └── providers/
│   │       └── auth_service.dart              # All Supabase auth operations
│   ├── dashboard/
│   │   ├── screens/
│   │   │   ├── main_shell.dart                # Bottom nav container (4 tabs)
│   │   │   └── dashboard_screen.dart          # Home tab with stats & actions
│   │   └── widgets/
│   ├── customers/
│   │   ├── screens/
│   │   │   ├── customers_screen.dart          # Customer list with search
│   │   │   └── add_customer_screen.dart       # Add/edit customer form
│   │   └── widgets/
│   ├── orders/
│   │   ├── screens/
│   │   │   ├── orders_screen.dart             # Orders list with filters & search
│   │   │   ├── select_customer_screen.dart    # Pick customer for new order
│   │   │   ├── select_garment_screen.dart     # Pick garment type & sub-types
│   │   │   ├── measurement_screen.dart        # Enter/edit measurements
│   │   │   ├── order_details_screen.dart      # Final order details & confirm
│   │   │   └── order_view_screen.dart         # View order + PDF + WhatsApp
│   │   └── widgets/
│   │       └── extra_instructions_widget.dart  # Voice/text instruction input
│   └── settings/
│       └── screens/
│           ├── settings_screen.dart           # Settings with logout
│           ├── edit_profile_screen.dart        # Edit shop profile
│           └── change_password_screen.dart     # Change password
├── models/
│   ├── customer.dart                          # Customer data model
│   ├── order.dart                             # Order data model
│   └── measurement.dart                       # Measurement data model
├── l10n/
│   ├── en.json                                # English translations
│   └── ur.json                                # Urdu translations
└── main.dart                                  # App entry point
```

## Authentication Flow
1. **First launch:** Language Selection → Sign Up screen
2. **Sign Up:** Owner Name, Phone, Shop Name, Address, Email, Password, Confirm Password → OTP sent to email → verify 6-digit code → profile saved to Supabase `shop_profiles` table → Dashboard
3. **Login (returning user):** Email + Password → Dashboard (no OTP needed)
4. **Session persistence:** User stays logged in until explicit logout
5. **Forgot Password:** Email → reset link sent

## Data Storage Strategy (CRITICAL)
- **Dual save:** Every data operation saves to LOCAL SQLite first (instant, offline), then syncs to Supabase cloud (backup)
- **New device login:** Downloads all cloud data to local SQLite on first login
- **Offline mode:** App works fully from local data when no internet
- **SyncService** (lib/core/database/sync_service.dart) handles all dual save operations
- **NEVER save data only locally or only to cloud - ALWAYS both**

## Supabase Tables
1. **shop_profiles** - Shop owner account info (id, owner_name, phone, shop_name, address, email)
2. **customers** - Customer records (id, user_id, name, phone, gender, serial_number, created_at, updated_at)
3. **orders** - Order records (id, user_id, customer_id, stitch_type, customer_gender, shirt_sub_type, bottom_type, bottom_waistband, elastic_width, quantity, colors, total_amount, advance_payment, delivery_date, status, special_instructions, extra_instructions, created_at, updated_at)
4. **measurements** - Measurement records (id, user_id, customer_id, order_id, garment_type, measurement_data, additional_options, created_at, updated_at)
5. **dupatta_details** - Dupatta finishing details (id, user_id, order_id, included, finishing, pico_coverage, pico_type, piping_coverage, lace_coverage, lace_provided_by_customer, created_at, updated_at)
- All tables have Row Level Security (RLS) - users can only access their own data via `auth.uid() = user_id`

## Local SQLite Tables
Same structure as Supabase but without `user_id` column (only one user per device)
- **Database version:** 2 (upgraded from 1 — drops old orders/measurements tables and recreates with new schema)

## Customer Model
- **Fields:** id (UUID), name, phone, gender (male/female), serial_number (auto-increment), created_at, updated_at
- **NO address, NO notes, NO email** for customers - keep it simple
- Serial number auto-assigns: first customer = #1, second = #2, etc.

## Design System
- **Primary Color:** Teal (#26A69A) with gradient to #00897B
- **Style:** Modern, clean, soft shadows, rounded corners (16px cards, 18px buttons)
- **Cards:** White background, subtle box shadows, no harsh borders
- **Buttons:** Gradient teal for primary actions, outlined for secondary
- **Empty States:** Icon in colored circle + descriptive text
- **Font sizes:** Labels 14px, body 15-16px, headings 18-24px
- **Mobile-first:** All designs must look good on Android phone (360-400px width)
- **App name styling:** "Ezee" (light weight) + "Book" (bold) - split typography

## Key Design Decisions Made
- Dashboard header: Compact teal gradient, centered app name only (NO shop name/owner name on dashboard)
- Stat cards: White cards with colored icon circles, vertical layout
- Action buttons: Large with 46-48px icon boxes, gradient primary, outlined secondary
- Bottom nav: 4 tabs (Home, Customers, Orders, Settings), teal active, gray inactive
- Gender selector: Tappable buttons (not dropdown)

## Important Rules
1. **Android only** - never reference iOS-specific code
2. **Offline-first** - every feature must work without internet
3. **Bilingual** - every user-facing string must be in both en.json and ur.json
4. **RTL support** - Urdu is right-to-left, designs must handle this
5. **Simple forms** - tailors are not tech-savvy, minimize required fields
6. **No address/notes for customers** - only name, phone, gender, serial number
7. **Pakistani context** - use Pakistani phone format (03XX), currency (PKR/Rs), measurement terms (Lambai, Chati, etc.)
8. **Windows desktop testing** - use `sqflite_common_ffi` for Windows compatibility
9. **Supabase keys** - stored in lib/core/constants/supabase_config.dart, never hardcode elsewhere
10. **Translations** - always add new strings to BOTH en.json and ur.json

## Current Status (What's Working)
- ✅ Flutter environment setup
- ✅ Consent screen (data consent + terms, replaces language selection; language switching is v1.1)
- ✅ Sign up with email + password + OTP
- ✅ Login with email + password
- ✅ Forgot password
- ✅ Dashboard with LIVE stat cards (real customer count, active orders, overdue orders)
- ✅ Dashboard today's deliveries section with "Mark Done" button
- ✅ Dashboard refreshes stats when returning from other screens or switching tabs
- ✅ Bottom navigation (4 tabs)
- ✅ Settings screen with logout, edit profile, change password
- ✅ Supabase connected (auth + shop_profiles + customers + orders + measurements + dupatta_details tables)
- ✅ SyncService for dual local+cloud saves (all CRUD operations)
- ✅ Cloud data download on new device login
- ✅ Customer management — add/edit/delete with dual save, search, serial numbers
- ✅ Full order placement flow: select customer → select garment → measurements → order details → confirm
- ✅ Order list screen with status filters (All, Pending, Completed, Delivered, Overdue) and search
- ✅ Order view screen with status management (Pending → Completed → Delivered, or Cancel)
- ✅ Overdue order detection (pending orders past delivery date flagged at display time)
- ✅ Measurements system — Pakistani garment measurements for men & women (Shalwar Kameez, Trouser, Choli, Sharara, etc.)
- ✅ Saved measurements reuse — prompts to reuse previous measurements for returning customers
- ✅ Additional measurement options (collar nok, side pocket, waistband type, elastic width, etc.)
- ✅ Dupatta details (finishing, pico, piping, lace options)
- ✅ Extra instructions with voice input (Android) and text input
- ✅ PDF generation for orders (professional receipt with shop info, customer, garment, measurements, instructions)
- ✅ PDF print preview and share via WhatsApp/other apps
- ✅ WhatsApp integration — order confirmation, pickup notification, order summary sharing
- ✅ All auth messages localized (English + Urdu)
- ✅ flutter analyze: ZERO issues

## What Needs To Be Built Next
1. **Customer detail screen** - tap customer to see their info + all orders history
2. **Edit existing orders** - currently can only view, not edit after creation
3. **Language switching** in Settings (currently only set at first launch)
4. **Urdu/RTL testing** on all screens
5. **Urdu font in PDF** - PDF currently English-only, needs NotoNastaliqUrdu font support
6. **Notifications** - reminder for upcoming deliveries
7. **Data export** - export customer/order data
8. **Android phone testing** and Play Store publishing
9. **Riverpod migration** - replace StatefulWidget state management with Riverpod
10. **go_router migration** - replace Navigator.push with go_router

## Windows Desktop Testing Notes
- sqflite doesn't work on Windows natively - must use sqflite_common_ffi
- In main.dart: `if (Platform.isWindows || Platform.isLinux) { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; }`
- Chrome/Edge testing doesn't work (window closes immediately) - use `flutter run -d windows`
- Hot reload works, but sometimes need `flutter clean && flutter pub get` for stubborn cache issues

## Common Pitfalls
- pubspec.yaml: assets and fonts must be INSIDE the `flutter:` block (indented with 2 spaces)
- Translation files: must be listed in pubspec.yaml assets as `- lib/l10n/`
- After `flutter clean`: always run `flutter pub get` before `flutter run`
- Supabase RLS: if data isn't saving to cloud, check that `user_id` is included in the insert
- Database schema changes: must delete old database file and restart (or increment version number)

## Session Log

### 2026-05-18: Subscription overhaul (Sessions 1–5)
- AccessGate widget created (lib/core/widgets/access_gate.dart)
  centralizes subscription gating; closes B1+B2+items 9,13
- TimeService gained monotonic clock cross-check for frozen-time defense
- promo_redemptions table + redeem_promo_code RPC added in Supabase
  for atomic promo code redemption
- Edge Function 'verify-receipt' deployed (currently STUB)
- billing_service routes Play purchases through server verification
- createSubscription accepts verifiedExpiresAt for server-authoritative
  expiry (auto-renewing model)

## Infrastructure
- Google Cloud project: ezeebook-receipts (number: 449543207259)
- Service Account: ezeebook-receipt-verifier@ezeebook-receipts.iam.gserviceaccount.com
- Service Account JSON: F:\dev\ezeebook-secrets\service-account-key.json
- Supabase Edge Function URL:
  https://bnnhchdqkrfovyrhuhxg.supabase.co/functions/v1/verify-receipt
- Supabase CLI installed via Scoop (v2.100.0)

## Play Console
- Developer account: Usconnect Solutions (Personal account)
- Account ID: 8720441359991860894
- Status: Identity verification in progress (purchased 2026-05-18)
- Awaiting approval before Session 6 can proceed

## v1.1 Backlog (deferred from audit)
- Item 11: Plan ID display (verify cloud schema after Play Console setup)
- refreshIfPossible rate-limiting (currently every 60s = high RPC volume)
- "Connection required" wording → "Time verification failed"
- Measurement input validation (no value > 100 inches)
- Per-shop branding in PDFs (logo, footer)
- Trial banner UX during timeUnverified state
- Type B recurring discount promos (via Play Console Offer Codes)