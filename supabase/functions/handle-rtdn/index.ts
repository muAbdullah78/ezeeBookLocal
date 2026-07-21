// handle-rtdn — Google Play RTDN webhook + Logging (Phase M4)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth, OAuth2Client } from "npm:google-auth-library@9";

const PACKAGE_NAME = "com.usconnect.ezeebook";
const ANDROID_PUBLISHER_BASE =
  "https://androidpublisher.googleapis.com/androidpublisher/v3";
const FUNCTION_NAME = "handle-rtdn";

const EXPECTED_AUDIENCE =
  "https://bnnhchdqkrfovyrhuhxg.supabase.co/functions/v1/handle-rtdn";
const AUTHORIZED_EMAIL =
  "ezeebook-receipt-verifier@ezeebook-receipts.iam.gserviceaccount.com";

const NT_RECOVERED = 1;
const NT_RENEWED = 2;
const NT_CANCELED = 3;
const NT_PURCHASED = 4;
const NT_ON_HOLD = 5;
const NT_IN_GRACE_PERIOD = 6;
const NT_RESTARTED = 7;
const NT_PRICE_CHANGE_CONFIRMED = 8;
const NT_DEFERRED = 9;
const NT_PAUSED = 10;
const NT_PAUSE_SCHEDULE_CHANGED = 11;
const NT_REVOKED = 12;
const NT_EXPIRED = 13;
const NT_PENDING_PURCHASE_CANCELED = 20;

interface PubSubEnvelope {
  message: {
    data: string;
    messageId?: string;
    publishTime?: string;
    attributes?: Record<string, string>;
  };
  subscription: string;
}

interface RtdnPayload {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    version?: string;
    notificationType: number;
    purchaseToken: string;
    subscriptionId: string;
  };
  testNotification?: { version?: string };
  voidedPurchaseNotification?: unknown;
  oneTimeProductNotification?: unknown;
}

interface PlayApiSubscription {
  startTimeMillis?: string;
  expiryTimeMillis?: string;
  autoRenewing?: boolean;
  paymentState?: number;
  acknowledgementState?: number;
  cancelReason?: number;
}

// ============ INLINE LOGGER ============
let _logClient: ReturnType<typeof createClient> | null = null;
function getLogClient() {
  if (_logClient) return _logClient;
  _logClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
  return _logClient;
}

function log(opts: {
  level: "info" | "warn" | "error";
  message: string;
  userId?: string | null;
  metadata?: Record<string, unknown>;
  durationMs?: number | null;
  status?: string | null;
  ipAddress?: string | null;
}) {
  try {
    const client = getLogClient();
    client
      .from("edge_function_logs")
      .insert({
        function_name: FUNCTION_NAME,
        level: opts.level,
        message: opts.message,
        user_id: opts.userId ?? null,
        metadata: opts.metadata ?? null,
        duration_ms: opts.durationMs ?? null,
        status: opts.status ?? null,
        ip_address: opts.ipAddress ?? null,
      })
      .then((res: { error: unknown }) => {
        if (res.error) console.error("log insert failed:", res.error);
      });
  } catch (e) {
    console.error("log threw:", e);
  }
}

function redactToken(token: string): string {
  if (!token || token.length < 12) return "***";
  return "***" + token.slice(-8);
}

function notificationTypeLabel(type: number): string {
  const labels: Record<number, string> = {
    1: "RECOVERED",
    2: "RENEWED",
    3: "CANCELED",
    4: "PURCHASED",
    5: "ON_HOLD",
    6: "IN_GRACE_PERIOD",
    7: "RESTARTED",
    8: "PRICE_CHANGE_CONFIRMED",
    9: "DEFERRED",
    10: "PAUSED",
    11: "PAUSE_SCHEDULE_CHANGED",
    12: "REVOKED",
    13: "EXPIRED",
    20: "PENDING_PURCHASE_CANCELED",
  };
  return labels[type] ?? `UNKNOWN(${type})`;
}
// ============ END LOGGER ============

let cachedAuth: GoogleAuth | null = null;
const oauthClient = new OAuth2Client();

function getGoogleAuth(): GoogleAuth {
  if (cachedAuth) return cachedAuth;
  const b64 = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64");
  if (!b64) throw new Error("Missing GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64");
  const credentials = JSON.parse(atob(b64));
  cachedAuth = new GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  return cachedAuth;
}

async function fetchSubscriptionState(
  purchaseToken: string,
  productId: string,
): Promise<PlayApiSubscription | null> {
  try {
    const client = await getGoogleAuth().getClient();
    const accessToken = await client.getAccessToken();
    if (!accessToken.token) return null;
    const url =
      `${ANDROID_PUBLISHER_BASE}/applications/${PACKAGE_NAME}` +
      `/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken.token}` },
    });
    if (!response.ok) {
      console.error(`Play API fetch failed ${response.status}`);
      return null;
    }
    return await response.json() as PlayApiSubscription;
  } catch (e) {
    console.error("Exception fetching subscription state:", e);
    return null;
  }
}

function getSupabaseAdmin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

async function verifyOidcToken(authHeader: string | null): Promise<boolean> {
  if (!authHeader) return false;
  const match = authHeader.match(/^Bearer\s+(.+)$/);
  if (!match) return false;
  const token = match[1];

  try {
    const ticket = await oauthClient.verifyIdToken({
      idToken: token,
      audience: EXPECTED_AUDIENCE,
    });
    const payload = ticket.getPayload();
    if (!payload) return false;
    if (payload.email !== AUTHORIZED_EMAIL) {
      console.error(`Wrong email in token: ${payload.email}`);
      return false;
    }
    if (payload.email_verified !== true) {
      console.error("Email not verified");
      return false;
    }
    return true;
  } catch (e) {
    console.error("OIDC verification failed:", e);
    return false;
  }
}

function buildUpdatePayload(
  notificationType: number,
  playState: PlayApiSubscription | null,
  eventTime: string,
): Record<string, unknown> | null {
  const base: Record<string, unknown> = {
    last_notification_type: notificationType,
    last_notification_at: eventTime,
    updated_at: eventTime,
  };
  const endDateFromPlay = playState?.expiryTimeMillis
    ? new Date(parseInt(playState.expiryTimeMillis, 10)).toISOString()
    : null;

  switch (notificationType) {
    case NT_RECOVERED:
      return {
        ...base,
        status: "active",
        on_hold_since: null,
        grace_period_ends_at: null,
        end_date: endDateFromPlay ?? undefined,
        auto_renewing: playState?.autoRenewing ?? true,
      };
    case NT_RENEWED:
      return {
        ...base,
        status: "active",
        end_date: endDateFromPlay ?? undefined,
        auto_renewing: playState?.autoRenewing ?? true,
      };
    case NT_CANCELED:
      return { ...base, cancelled_at: eventTime, auto_renewing: false };
    case NT_PURCHASED:
      return base;
    case NT_ON_HOLD:
      return { ...base, status: "on_hold", on_hold_since: eventTime };
    case NT_IN_GRACE_PERIOD:
      return { ...base, grace_period_ends_at: endDateFromPlay ?? undefined };
    case NT_RESTARTED:
      return {
        ...base,
        status: "active",
        cancelled_at: null,
        auto_renewing: true,
      };
    case NT_REVOKED:
      return { ...base, status: "revoked", cancelled_at: eventTime };
    case NT_EXPIRED:
      return { ...base, status: "expired", auto_renewing: false };
    case NT_DEFERRED:
      return { ...base, end_date: endDateFromPlay ?? undefined };
    case NT_PAUSED:
    case NT_PAUSE_SCHEDULE_CHANGED:
    case NT_PRICE_CHANGE_CONFIRMED:
    case NT_PENDING_PURCHASE_CANCELED:
      return base;
    default:
      console.warn(`Unknown notification type: ${notificationType}`);
      return base;
  }
}

Deno.serve(async (req) => {
  const startTime = Date.now();
  const ipAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Verify OIDC token from Pub/Sub
    const authHeader = req.headers.get("Authorization");
    const isAuthorized = await verifyOidcToken(authHeader);
    if (!isAuthorized) {
      log({
        level: "warn",
        message: "Rejected unauthorized RTDN request",
        ipAddress,
        status: "unauthorized",
        durationMs: Date.now() - startTime,
      });
      console.warn("Rejected unauthorized request");
      return new Response("Unauthorized", { status: 401 });
    }

    let envelope: PubSubEnvelope;
    try {
      envelope = await req.json() as PubSubEnvelope;
    } catch {
      log({
        level: "warn",
        message: "Invalid Pub/Sub envelope JSON",
        ipAddress,
        status: "invalid_envelope",
        durationMs: Date.now() - startTime,
      });
      console.error("Invalid Pub/Sub envelope");
      return new Response("Bad Request", { status: 400 });
    }

    if (!envelope.message?.data) {
      log({
        level: "warn",
        message: "Missing message.data in envelope",
        ipAddress,
        status: "invalid_envelope",
        metadata: { messageId: envelope.message?.messageId },
        durationMs: Date.now() - startTime,
      });
      console.error("Missing message.data");
      return new Response("Bad Request", { status: 400 });
    }

    let payload: RtdnPayload;
    try {
      payload = JSON.parse(atob(envelope.message.data)) as RtdnPayload;
    } catch (e) {
      log({
        level: "warn",
        message: "Failed to decode payload",
        ipAddress,
        status: "invalid_payload",
        metadata: {
          messageId: envelope.message?.messageId,
          error: e instanceof Error ? e.message : String(e),
        },
        durationMs: Date.now() - startTime,
      });
      console.error("Failed to decode payload:", e);
      return new Response("Bad Request", { status: 400 });
    }

    // Test notifications (Play Console test button)
    if (payload.testNotification) {
      log({
        level: "info",
        message: "Test notification received (RTDN setup working)",
        ipAddress,
        status: "test",
        metadata: { version: payload.testNotification.version },
        durationMs: Date.now() - startTime,
      });
      console.log("Received test notification — RTDN setup working");
      return new Response("OK", { status: 200 });
    }

    if (
      payload.voidedPurchaseNotification || payload.oneTimeProductNotification
    ) {
      log({
        level: "info",
        message: "Non-subscription notification received, ignored",
        ipAddress,
        status: "ignored",
        metadata: {
          kind: payload.voidedPurchaseNotification
            ? "voided"
            : "one_time_product",
        },
        durationMs: Date.now() - startTime,
      });
      console.log("Received non-subscription notification, ignoring");
      return new Response("OK", { status: 200 });
    }

    const notification = payload.subscriptionNotification;
    if (!notification) {
      log({
        level: "info",
        message: "No subscriptionNotification in payload, ignored",
        ipAddress,
        status: "ignored",
        durationMs: Date.now() - startTime,
      });
      console.log("No subscriptionNotification in payload, ignoring");
      return new Response("OK", { status: 200 });
    }

    const { notificationType, purchaseToken, subscriptionId } = notification;
    const eventTime = new Date(
      parseInt(payload.eventTimeMillis ?? Date.now().toString(), 10),
    ).toISOString();

    log({
      level: "info",
      message: `RTDN received: ${notificationTypeLabel(notificationType)}`,
      ipAddress,
      metadata: {
        notification_type: notificationType,
        notification_label: notificationTypeLabel(notificationType),
        subscription_id: subscriptionId,
        purchase_token_redacted: redactToken(purchaseToken),
        event_time: eventTime,
      },
    });

    console.log(
      `RTDN: type=${notificationType}, product=${subscriptionId}, eventTime=${eventTime}`,
    );

    if (payload.packageName !== PACKAGE_NAME) {
      log({
        level: "warn",
        message: "Package name mismatch",
        ipAddress,
        status: "package_mismatch",
        metadata: {
          got: payload.packageName,
          expected: PACKAGE_NAME,
        },
        durationMs: Date.now() - startTime,
      });
      console.error(
        `Package name mismatch: got ${payload.packageName}, expected ${PACKAGE_NAME}`,
      );
      return new Response("OK", { status: 200 });
    }

    const playState = await fetchSubscriptionState(
      purchaseToken,
      subscriptionId,
    );

    if (!playState) {
      log({
        level: "warn",
        message: "Failed to fetch subscription state from Play API",
        ipAddress,
        status: "play_api_fetch_failed",
        metadata: {
          notification_type: notificationType,
          subscription_id: subscriptionId,
          purchase_token_redacted: redactToken(purchaseToken),
        },
      });
      // Continue anyway — some updates don't need fresh Play API state
    }

    const updatePayload = buildUpdatePayload(
      notificationType,
      playState,
      eventTime,
    );

    if (!updatePayload) {
      return new Response("OK", { status: 200 });
    }

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("user_subscriptions")
      .update(updatePayload)
      .eq("purchase_token", purchaseToken)
      .select("id, user_id, status");

    if (error) {
      log({
        level: "error",
        message: "DB update failed",
        ipAddress,
        status: "db_error",
        metadata: {
          notification_type: notificationType,
          purchase_token_redacted: redactToken(purchaseToken),
          db_error: error.message,
        },
        durationMs: Date.now() - startTime,
      });
      console.error(
        `DB update failed for token=${purchaseToken.substring(0, 20)}...:`,
        error,
      );
      return new Response("Internal error", { status: 500 });
    }

    if (!data || data.length === 0) {
      log({
        level: "warn",
        message: "No matching subscription found for token",
        ipAddress,
        status: "orphan_token",
        metadata: {
          notification_type: notificationType,
          notification_label: notificationTypeLabel(notificationType),
          purchase_token_redacted: redactToken(purchaseToken),
          subscription_id: subscriptionId,
        },
        durationMs: Date.now() - startTime,
      });
      console.warn(
        `No subscription found for token=${purchaseToken.substring(0, 20)}...`,
      );
      return new Response("OK", { status: 200 });
    }

    log({
      level: "info",
      message:
        `RTDN processed: ${notificationTypeLabel(notificationType)} → ${
          data[0].status
        }`,
      userId: data[0].user_id,
      ipAddress,
      status: "success",
      metadata: {
        notification_type: notificationType,
        notification_label: notificationTypeLabel(notificationType),
        subscription_id: subscriptionId,
        subscription_db_id: data[0].id,
        new_status: data[0].status,
        purchase_token_redacted: redactToken(purchaseToken),
      },
      durationMs: Date.now() - startTime,
    });

    console.log(
      `Updated subscription id=${data[0].id}, user=${
        data[0].user_id
      }, new_status=${data[0].status}`,
    );

    return new Response("OK", { status: 200 });
  } catch (e) {
    // Uncaught exception
    const errorMessage = e instanceof Error ? e.message : String(e);
    const errorStack = e instanceof Error ? e.stack : undefined;
    log({
      level: "error",
      message: "Uncaught exception in handle-rtdn",
      ipAddress,
      status: "exception",
      metadata: { error: errorMessage, stack: errorStack },
      durationMs: Date.now() - startTime,
    });
    console.error("handle-rtdn uncaught:", e);
    return new Response("Internal error", { status: 500 });
  }
});