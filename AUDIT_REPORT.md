# EzeeBook — Independent Pre-Launch Audit

*Read-only adversarial review. Nothing on disk was modified. Reviewer has no stake in how the app was built.*

Scope reviewed: the whole `lib/` tree (55 Dart files), both Edge Functions the app calls (`verify-receipt`, `handle-rtdn`), Android manifests + Gradle, `en.json`/`ur.json`, splash/icon config, and git history.

---

## 1. Rejection Risks

### R1 — Trial length in the code (72 hours) contradicts the "14-day trial" you're launching on. ✗ CRITICAL
**Where:** `lib/core/services/subscription_service.dart:337` and `:350` — `createdAt.add(const Duration(hours: 72))`.
**Observed:** The only trial logic in the app is a hard **72-hour** window from account-creation time. There is no 14-day trial anywhere in the code. Your own brief describes the product as having a "14-day trial," and the CLAUDE.md session log calls the 72h a "grace period." Both framings are wrong: 72 hours **is** the entire free trial, and there is no separate grace period at all (see R2/D-series).
**Why it's a rejection/▲compliance risk:** If your Play Store listing, screenshots, or Play Console free-trial offer say "14 days" while the app locks the user out after 3 days, that is a *misleading claim* — a Play policy violation and a guaranteed 1-star review magnet. The screenshot you sent shows "Free trial — 2 day(s) remaining," confirming the 72h path is what ships.
**Developer framing:** Presented as an "intentional 72-hour grace period." It is not a grace period and it is not 14 days. Not defensible as-labelled — at minimum the number must match your store listing and be a deliberate decision, not an accident of a leftover constant.
**Fix:** Decide the real trial length, put it in one named constant, and make the store listing + Play Console offer + in-app banner all agree.

### R2 — No Google Play grace-period / account-hold handling on the client. ✗
**Where:** `access_gate.dart:99-123`; `handle-rtdn/index.ts:245-259` writes `grace_period_ends_at`, `on_hold_since` to the cloud row, but **no client code ever reads those columns** (`grep` for `grace_period`/`on_hold` in `lib/` returns only unrelated time-service comments).
**Observed:** When a Play subscription enters Google's grace period (payment failed but Google is retrying) or account-hold, the RTDN webhook records it server-side, but `AccessGate` only checks `end_date > now` OR the 72h trial. The moment `end_date` passes, the user is locked out — even though Google policy expects the app to keep serving during the grace period.
**Why it's a rejection risk:** Google's subscription policy specifically wants apps to honor grace periods; locking paying users out mid-grace causes involuntary churn and refund disputes, and contradicts the auto-renew disclosure you show. It also wastes the RTDN infrastructure that was built.
**Fix:** In `AccessGate`, treat `status in ('active','in_grace','on_hold')` with a valid `grace_period_ends_at` as access-granted; read those columns down in `downloadAllData`/`hasActiveSubscription`.

### R3 — `RECORD_AUDIO` permission requires a prominent disclosure + Data-Safety declaration. ⚠
**Where:** `android/app/src/main/AndroidManifest.xml:3`.
**Observed:** Mic permission is declared for voice input. The in-app rationale dialog (`extra_instructions_widget.dart:127-174`) is good, but Play's Data Safety form and (for microphone) a prominent in-context disclosure are mandatory.
**Why:** Microphone is a "sensitive" permission; undeclared use is a common rejection cause.
**Fix:** Ensure the Play Console Data Safety form lists audio + all PII (email, phone, name, address, measurements) and that the privacy policy names them. Cannot be verified from code — verify in Console before submit.

### R4 — Release build silently falls back to the **debug** signing key. ✗
**Where:** `android/app/build.gradle.kts:50-54` — if `key.properties` is absent, `release` uses `signingConfigs.getByName("debug")`.
**Why it's a rejection/▲publish risk:** A release AAB accidentally signed with the debug key cannot be published (or, worse, gets published and can never be updated because the upload key is wrong). `isMinifyEnabled = false` and `isShrinkResources = false` also mean **no obfuscation and no shrinking** — larger APK and fully readable decompiled source. Not a hard rejection, but poor release hygiene for a paid app whose paywall logic is client-side.
**Fix:** Make release fail loudly if `key.properties` is missing; enable R8/minify + resource shrinking with a tested ProGuard config.

**Everything else in this bucket: no illegal-content, ad-policy, or families-policy patterns found. Account deletion (Play requirement) is implemented in-app and server-side — good.**

---

## 2. Data-Loss Risks

### D1 — Every login/signup wipes all local data *before* the network call; unsynced offline data is lost forever. ✗ CRITICAL
**Where:** `auth_service.dart:15-29` (`_wipeLocalState` → `DatabaseHelper().deleteAllData()`), called at the top of `login()` (`:92`), `signUp()` (`:33`), and `signOut()` (`:164`). Cloud writes are fire-and-forget (`sync_service.dart` — every `catch` only logs).
**Failure scenario:** Tailor uses the app offline (the whole selling point). A customer/order is saved locally; the cloud upsert throws because there's no internet, and the error is swallowed. The tailor later logs out and back in (or reinstalls) → `_wipeLocalState()` clears SQLite, then `downloadAllData()` pulls from a cloud that never received the offline records. **Data gone, silently.**
**Why it matters:** This directly breaks the "offline-first, never lose data" promise for the exact user who works offline. There is no per-record dirty flag and no durable outbound queue — sync relies on `uploadAllData()` firing on a reconnect *event* or on next login, neither guaranteed before a wipe.
**Fix:** Don't wipe on same-user re-login; wipe only on actual account switch. Add a "pending upload" flag per row and flush it before any destructive local operation.

### D2 — No unsaved-changes protection on any form; back-navigation silently discards everything. ✗
**Where:** `measurement_screen.dart` (a 1,600-line form with dozens of fields), `order_details_screen.dart`, `add_customer_screen.dart`. None use `PopScope`/`WillPopScope` or a confirm-on-exit.
**Failure scenario:** Tailor spends two minutes entering 13 kameez + 6 shalwar measurements, accidentally hits the system back gesture (Android 15 predictive-back makes this easier), and loses all of it with no warning. High-frequency, high-frustration for a low-literacy user.
**Fix:** Guard the measurement and order-details screens with a "Discard changes?" dialog when the form is dirty.

### D3 — Cloud-write failures during online use are never retried until a reconnect event. ⚠
**Where:** `sync_service.dart:150-327` — `saveCustomer`, `saveOrder`, `updateOrder`, `saveMeasurement`, etc. all do local-write-then-cloud-upsert inside a `try/catch` that only logs. Retry only happens via the `ConnectivityHelper` reconnect listener (`main.dart:112`) or next login.
**Impact:** A transient network blip mid-session leaves the cloud stale with no automatic recovery that session; combined with D1 this is how records disappear.
**Fix:** A proper outbox with retry/backoff, or at minimum re-run `uploadAllData()` on app resume.

### D4 — Last-write-wins by `updated_at` can clobber a second device's edits. ⚠
**Where:** `sync_service.dart:575-594` (`_shouldOverwriteLocal`) and `downloadAllData`. Parse failure defaults to "overwrite local." No field-level merge.
**Impact:** Low for the typical one-device tailor, real if a shop uses two phones (owner + worker). Newer-timestamp wins wholesale.
**Fix:** Acceptable for v1 if single-device; document it, and revisit before any multi-device/karigar feature.

### D5 — Dead deletion path with different semantics than the shipped one. ⚠
**Where:** `sync_service.dart:598-623` (`deleteAllUserData` calls an RPC `delete_user`) is never invoked; the Settings screen uses `AccountDeletionService` → the `delete-account` Edge Function instead. Two parallel deletion mechanisms, one unused.
**Impact:** Confusing, and if anyone wires the dead one up it depends on an RPC that may not exist. Remove it.

---

## 3. Security Findings

### S1 — Subscription is written **twice** per purchase, the second time with a client-computed expiry that bypasses server verification. ✗ CRITICAL (integrity + monetization)
**Where:** `billing_service.dart:162-174` calls `createSubscription(..., verifiedExpiresAt: result.expiresAt, purchaseToken: ...)` (server-authoritative). It then fires `onPurchaseComplete(planId, success)`. Both `subscription_screen.dart:49-56` and `subscription_lock_screen.dart:49-53` handle that callback by calling `createSubscription(planId, paymentMethod: 'play_billing')` **again — with no `verifiedExpiresAt`**, so `subscription_service.dart:229-238` computes the expiry locally from `now + duration`. `createSubscription` mints a fresh UUID each call (`:239`), so two rows are inserted per purchase.
**Impact:** (a) Duplicate `user_subscriptions` rows per purchase. (b) The second, un-verified row carries a client-clock expiry — defeating the whole server-verification design and making expiry spoofable by anyone who can influence the device clock at purchase time. `getActiveSubscription` orders by `end_date DESC`, so the client-computed row can win.
**Fix:** The screens must **not** re-create the subscription; `billing_service` already did it with the verified expiry. The callback should only route the UI.

### S2 — Any valid promo code grants a full-length subscription for free, regardless of discount. ✗ (monetization loophole)
**Where:** `subscription_screen.dart:120-170`. The promo path computes `finalPrice` (even partial discounts) then calls `createSubscription(planId, promoCode: ...)` — which **never charges anything and never touches Play Billing**. `finalPrice` is passed but ignored by `createSubscription` (`subscription_service.dart:205`).
**Failure scenario:** A "10% off" promo, or any leaked code, yields a 100%-free active subscription. There is no payment step on the promo branch at all.
**Why it's dangerous:** Codes leak (screenshots, WhatsApp groups). This is a direct revenue bypass.
**Fix:** Promo codes should apply a discount to a *Play Billing* purchase (or be limited to genuine 100%-off comps with tight server-side caps). Never grant paid access without a payment or an explicit free-comp flag.

### S3 — `AccessGate` fails **open** on any unexpected error. ⚠
**Where:** `access_gate.dart:124-132` — the catch-all sets state to `granted` ("brief access during error states is acceptable for v1").
**Impact:** A user who can reliably trigger an exception in the evaluation path (e.g., corrupt local sub row) gets the app unlocked. Combined with S1's client-trusted expiry, the paywall is softer than it looks.
**Fix:** Fail closed to the lock screen (with a retry), not open.

### S4 — Supabase anon key committed to git from the first commit. ⚠ (low, but confirm RLS)
**Where:** `lib/core/constants/supabase_config.dart:6` (tracked; present since initial commit).
**Assessment:** The **anon** key is designed to be shippable *if* Row-Level Security is correctly enabled on every table. `subscription_sql.dart` shows RLS on the subscription tables; customers/orders/measurements/dupatta RLS is asserted in CLAUDE.md but **cannot be verified from the mobile code**. The whole security model rests on server-side RLS.
**Fix / verify before launch:** Confirm in Supabase that RLS is ON with `auth.uid() = user_id` policies on `customers`, `orders`, `measurements`, `dupatta_details`, `shop_profiles`, and `user_subscriptions`. If any is missing, the anon key becomes a full data-exfiltration key.

### S5 — No code obfuscation/shrinking on release. ⚠
**Where:** `build.gradle.kts:55-56` (`isMinifyEnabled = false`, `isShrinkResources = false`).
**Impact:** Client-side paywall logic (which, per S1/S3, is already load-bearing) ships fully readable and trivially patchable. For a subscription app that's a poor combination.
**Fix:** Enable R8 + a tested ProGuard config; move the authoritative access decision server-side over time.

### S6 — Positive notes (genuinely good): ★
- `TimeService` (`time_service.dart`) is a well-thought-out anti-clock-spoofing design: cached server time + monotonic `Stopwatch` cross-check + rollback detection + 24h offline cap. This is above-average for a v1.
- `handle-rtdn` verifies the Pub/Sub **OIDC token** audience + service-account email + `email_verified` (`handle-rtdn/index.ts:182-208`) — correct and often skipped.
- `verify-receipt` is real Google Play Developer API verification with `paymentState`/expiry checks and token redaction in logs. Server-authoritative expiry is the right model (which S1 then undermines on the client — fix S1 and this becomes solid).
- Account deletion is server-first, then local wipe, then sign-out, and refuses to wipe local if the server delete fails (`account_deletion_service.dart:70-85`) — correct ordering.
- Sentry: `sendDefaultPii=false`, no screenshots/view-hierarchy — privacy-conscious defaults.

---

## 4. ✗ Poor (bad UX / dated / will hurt reputation)

- **P1 — Language toggle is advertised but does not exist.** `main.dart:81-84` hard-codes `supportedLocales: [Locale('en')]`, `startLocale: en`, and wraps the whole app in a forced `Directionality(TextDirection.ltr)` (`:172-177`). Every screen calls `.tr()` and there's a full `ur.json`, but **Urdu can never be shown** and **RTL is globally disabled**. The Settings "language toggle" in your feature list isn't in the Settings screen at all. So all the bilingual work (and the RTL slide-transition logic in `page_transitions.dart`) is dead. Either ship the toggle or stop advertising bilingual. This is the single biggest gap between claimed and actual behavior after the trial bug.
- **P2 — Dashboard notification bell is a no-op.** `dashboard_screen.dart:207-210` — `onPressed: () {}`. A visible, tappable control that does nothing reads as broken. Either wire it (see the growth doc — delivery reminders are a top retention feature) or remove it before launch. You already flagged this.
- **P3 — Urdu measurement hints are inconsistent and partly English/mixed.** `measurement_screen.dart` field hints mix scripts: `'w_chest'` hint is the literal string `'chest'`, `'w_front_neck'` is `'front گلا'`, `'w_cuff_opening'` label vs hint mismatches. For a low-literacy Urdu-first user reading measurement labels, this is confusing and looks unfinished.
- **P4 — PDF is English-only despite a bilingual app and bundled Urdu font.** `pdf_generator.dart:38` still has the `// TODO: Load Urdu font`. The receipt the customer receives (your key sharing artifact) can't render the customer's name, colors, or instructions in Urdu — they'll show as boxes/blanks if Urdu text is entered. The font is already in `assets/fonts/`; it's just not wired in.
- **P5 — Serial number is a free-text editable field on the customer form.** `add_customer_screen.dart:174-195` pre-fills the next serial but lets the user type any number, with no uniqueness check. Two customers can trivially share `#3`, and orders reference customers by serial in the UI. Make it read-only or enforce uniqueness.
- **P6 — Customer list has no detail screen; tapping a customer opens the *edit* form.** `customers_screen.dart:295` (`onTap: _navigateToEdit`). There's no way to see a customer's order history from their profile — a core expectation and something your own "what's next" list calls out. It makes the customer tab feel like a dead-end address book.
- **P7 — Orders can be viewed but never edited.** No edit path from `order_view_screen.dart`; a wrong price/date/measurement means cancel-and-recreate. For a shop that constantly adjusts orders this is painful.
- **P8 — `error_generic` shows raw exceptions to the user.** `add_customer_screen.dart:96` → `'error_generic'.tr(namedArgs:{'error':'$e'})`, and `change_password_screen.dart:48` shows `'$e'`. A tailor seeing a Dart stack-trace fragment is pure 2015. Map to friendly messages.

## 5. ⚠ Average (functional but dated / could be better)

- **A1 — No Material 3 dynamic color, no dark mode, no documented absence.** `app_theme.dart` is effectively an M2-styled theme on top of M3 (`elevation: 2` cards, hardcoded teal AppBar, no `ColorScheme` surface tokens used in widgets). Fine, but flat and 2020-ish; no dark theme at all (many low-end Androids default to battery-saver dark).
- **A2 — Colors and text styles are frequently hardcoded, bypassing the theme.** `AppTextStyles`/`AppColors` exist but screens routinely inline `Color(0xFF...)` and raw `TextStyle` (e.g., dashboard header gradient `0xFF2EC4B6`/`0xFF1A8C7E` differs from the brand `0xFF26A69A`; settings uses `0xFFF5F6FA`, `0xFF1A1A1A`, `0xFF6B7280` not in `AppColors`). Spacing is magic-number-driven, not on a 4/8/16 scale. Theme drift will make future restyling painful.
- **A3 — Search is not debounced and filters only in-memory.** `customers_screen.dart:48`, `orders_screen.dart:249` filter on every keystroke over the full list. Fine at 50 rows, janky at 2,000. No pagination anywhere — all customers/orders load into memory (`getAllCustomers`/`getAllOrdersWithCustomer` with no limit).
- **A4 — Trial banner / lock messaging is confusing.** `lock_time_unverified_title` = "Connection required" is shown when time can't be verified even if the user *is* online but the RPC failed; the message tells them to connect to the internet. Misleading. (Your own v1.1 backlog notes this.)
- **A5 — `refreshIfPossible()` + a 60s `AccessGate` timer + a 60s trial timer** all fire server-time RPCs frequently (`access_gate.dart:52`, `main_shell.dart:50`, `main.dart:74`). High RPC volume per active user; you flagged the rate-limiting in the backlog — worth doing before scale.
- **A6 — Measurement values have no validation.** No upper bound, no numeric sanity (`measurement_screen.dart` fields accept any decimal). A fat-fingered "1000 inch" length saves silently. Your backlog notes this.
- **A7 — Settings profile card reads directly from Supabase, not the offline cache.** `settings_screen.dart:82-100` queries `shop_profiles` from the network on every open; offline it silently shows blanks/email-only. Everything else in the app is local-first — this one screen isn't.
- **A8 — `select_garment_screen.dart` shows two women's garments as permanently "Coming soon" (disabled, greyed).** Shipping visible dead options ("One-piece suit", "Saari/Blouse") advertises missing features on day one. Hide until built.
- **A9 — Toast/snackbar overload in voice flow.** `extra_instructions_widget.dart` fires info snackbars for "nothing heard," "hold longer," "converting," etc. — reasonable, but stacked with the mic UX it's noisy on small screens.

## 6. ✓ Good (solid, no complaints)

- Consistent card/rounded-corner/teal visual language across screens; empty states exist on every list (customers, orders, select-customer) with icon + text.
- Order list has proper loading / empty / **error+retry** states (`orders_screen.dart:392-439`) — better than most.
- Skeleton shimmer for dashboard stats and settings profile (`shimmer_loading.dart`) — correct use of skeletons for content vs spinners for actions.
- OTP entry (`otp_screen.dart`) with per-box focus advancing, digit-only formatters, auto-submit; reset-password OTP has a 30s resend cooldown timer (`reset_password_otp_screen.dart:52-67`).
- Pull-to-refresh on customers and orders; haptics on quantity stepper (`order_details_screen.dart:115`).
- Voice input degrades gracefully (permission rationale dialog, "android only" guard, re-init on retry, status-callback recovery for engines that skip `onResult`).
- Localization *infrastructure* is disciplined: 430/430 keys present in both `en.json` and `ur.json`, `.tr()` used almost everywhere (see note in §7 on the ~62 identical values).

## 7. ★ Fantastic (2026-grade)

- **`TimeService` anti-tamper design** (see S6) — genuinely strong for a solo v1.
- **`verify-receipt` + `handle-rtdn` server stack** with OIDC verification, structured `edge_function_logs`, token redaction, and a full RTDN notification-type switch — this is production-grade backend plumbing that most indie Play apps never build. (Its value is currently blunted by the client-side S1/R2 gaps — close those and this becomes a real asset.)
- **Account-deletion flow**: reason capture, live data counts, typed-email confirmation, active-subscription warning with a deep link to Play to cancel, server-first delete ordering, dedicated success screen with back-button blocked. Thorough and compliant.

---

## Statistics
- **Files reviewed:** ~55 Dart files, 2 Deno Edge Functions, Gradle/Manifest/splash/icon configs, `en.json` + `ur.json`. Everything the mobile app touches.
- **Rough LOC:** ~17.5k Dart + ~0.95k TypeScript.
- **Screens audited:** ~25 (consent, login, signup, OTP, forgot-password, reset-password-OTP, subscription-lock, dashboard, customers, add/edit-customer, orders, select-customer, select-garment, measurements, order-details, order-view, extra-instructions, settings, subscription, edit-profile, change-password, about, delete-account, delete-success, main-shell).
- **Critical issues:** 5 — R1 (trial length), D1 (offline wipe data-loss), S1 (double-write/expiry bypass), S2 (promo = free sub), plus R2 (grace period) as a strong compliance risk.
- **Nice-to-have issues:** ~20 across buckets 4–5.

## What I could not verify from code alone (test these yourself before launch)
1. **Server-side RLS** on every table (S4) — the entire security model depends on it. Verify in the Supabase dashboard.
2. **Play Console Data Safety form + trial offer config** (R1, R3) — do they match the app's real 72h behavior and its real data collection?
3. **Whether `redeem_promo_code` / `delete_user` / `get_server_time` RPCs and the `subscription_plans`, `promo_codes`, `edge_function_logs` tables actually exist** in the deployed project with the columns the code expects (incl. the grace-period columns the RTDN writes).
4. **Real device behavior:** predictive-back on Android 15, edge-to-edge insets, animation smoothness, Urdu STT accuracy on real phones, contrast at low brightness — all need on-device testing.
5. **PDF rendering with Urdu text** (P4) — enter an Urdu customer name/instruction and open the PDF to see how badly it breaks today.
6. **Actual end-to-end purchase** on a real Play account — to confirm the S1 double-row actually lands (I'm confident from the code, but confirm in the DB).
