// handle-rtdn — receives Pub/Sub push notifications from Google Play
// Real-Time Developer Notifications (RTDN) about subscription events.
//
// Authentication: Pub/Sub sends OIDC bearer token. We verify:
//   - Token signature against Google's public keys
//   - Audience matches our function URL
//   - Email matches our authorized service account
//   - Token isn't expired
//
// Without valid OIDC, returns 401.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth, OAuth2Client } from "npm:google-auth-library@9";

const PACKAGE_NAME = "com.usconnect.ezeebook";
const ANDROID_PUBLISHER_BASE =
  "https://androidpublisher.googleapis.com/androidpublisher/v3";

// OIDC verification
const EXPECTED_AUDIENCE =
  "https://bnnhchdqkrfovyrhuhxg.supabase.co/functions/v1/handle-rtdn";
const AUTHORIZED_EMAIL =
  "ezeebook-receipt-verifier@ezeebook-receipts.iam.gserviceaccount.com";

// Google Play notification types
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

/**
 * Verifies the OIDC token from Pub/Sub.
 * Returns true if the request is from authorized Google Pub/Sub.
 */
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
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Verify OIDC token from Pub/Sub
  const authHeader = req.headers.get("Authorization");
  const isAuthorized = await verifyOidcToken(authHeader);
  if (!isAuthorized) {
    console.warn("Rejected unauthorized request");
    return new Response("Unauthorized", { status: 401 });
  }

  let envelope: PubSubEnvelope;
  try {
    envelope = await req.json() as PubSubEnvelope;
  } catch {
    console.error("Invalid Pub/Sub envelope");
    return new Response("Bad Request", { status: 400 });
  }

  if (!envelope.message?.data) {
    console.error("Missing message.data");
    return new Response("Bad Request", { status: 400 });
  }

  let payload: RtdnPayload;
  try {
    payload = JSON.parse(atob(envelope.message.data)) as RtdnPayload;
  } catch (e) {
    console.error("Failed to decode payload:", e);
    return new Response("Bad Request", { status: 400 });
  }

  // Test notifications (Play Console test button)
  if (payload.testNotification) {
    console.log("Received test notification — RTDN setup working");
    return new Response("OK", { status: 200 });
  }

  // Non-subscription notifications: ack and ignore
  if (payload.voidedPurchaseNotification || payload.oneTimeProductNotification) {
    console.log("Received non-subscription notification, ignoring");
    return new Response("OK", { status: 200 });
  }

  const notification = payload.subscriptionNotification;
  if (!notification) {
    console.log("No subscriptionNotification in payload, ignoring");
    return new Response("OK", { status: 200 });
  }

  const { notificationType, purchaseToken, subscriptionId } = notification;
  const eventTime = new Date(
    parseInt(payload.eventTimeMillis ?? Date.now().toString(), 10),
  ).toISOString();

  console.log(
    `RTDN: type=${notificationType}, product=${subscriptionId}, eventTime=${eventTime}`,
  );

  if (payload.packageName !== PACKAGE_NAME) {
    console.error(
      `Package name mismatch: got ${payload.packageName}, expected ${PACKAGE_NAME}`,
    );
    return new Response("OK", { status: 200 });
  }

  const playState = await fetchSubscriptionState(purchaseToken, subscriptionId);
  const updatePayload = buildUpdatePayload(notificationType, playState, eventTime);

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
    console.error(
      `DB update failed for token=${purchaseToken.substring(0, 20)}...:`,
      error,
    );
    return new Response("Internal error", { status: 500 });
  }

  if (!data || data.length === 0) {
    console.warn(
      `No subscription found for token=${purchaseToken.substring(0, 20)}...`,
    );
    return new Response("OK", { status: 200 });
  }

  console.log(
    `Updated subscription id=${data[0].id}, user=${data[0].user_id}, new_status=${data[0].status}`,
  );

  return new Response("OK", { status: 200 });
});