// verify-receipt Edge Function — REAL (Session 6)
//
// Verifies Google Play subscription purchase tokens server-side
// by calling the Google Play Developer API.
//
// REQUEST (POST body):
//   {
//     "purchase_token": "<token from Play Billing>",
//     "product_id": "ezeebook_monthly_1400",
//     "plan_id": "monthly"
//   }
//
// RESPONSE (success):
//   {
//     "valid": true,
//     "subscription": {
//       "product_id": "ezeebook_monthly_1400",
//       "expires_at": "2026-06-20T...",
//       "auto_renewing": true
//     }
//   }
//
// RESPONSE (failure):
//   {
//     "valid": false,
//     "reason": "unauthenticated" | "invalid_request" | "missing_fields"
//             | "token_not_found" | "token_expired" | "payment_not_received"
//             | "expired" | "auth_failed" | "play_api_error" | "exception"
//   }
//
// SECRETS REQUIRED:
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64 — base64-encoded service
//   account JSON with androidpublisher scope access.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Must match the package name in your AndroidManifest.xml
const PACKAGE_NAME = "com.usconnect.ezeebook";

const ANDROID_PUBLISHER_BASE =
  "https://androidpublisher.googleapis.com/androidpublisher/v3";

interface VerifyRequest {
  purchase_token: string;
  product_id: string;
  plan_id: string;
}

interface PlayApiSubscription {
  startTimeMillis?: string;
  expiryTimeMillis?: string;
  autoRenewing?: boolean;
  paymentState?: number;
  acknowledgementState?: number;
  cancelReason?: number;
  kind?: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

let cachedAuth: GoogleAuth | null = null;

function getGoogleAuth(): GoogleAuth {
  if (cachedAuth) return cachedAuth;

  const b64 = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64");
  if (!b64) {
    throw new Error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64 not configured");
  }

  const jsonStr = atob(b64);
  const credentials = JSON.parse(jsonStr);

  cachedAuth = new GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });

  return cachedAuth;
}

async function callPlayApi(
  purchaseToken: string,
  productId: string,
): Promise<{ data?: PlayApiSubscription; error?: string }> {
  try {
    const auth = getGoogleAuth();
    const client = await auth.getClient();
    const accessTokenResponse = await client.getAccessToken();

    if (!accessTokenResponse.token) {
      console.error("Failed to obtain Google access token");
      return { error: "auth_failed" };
    }

    const url =
      `${ANDROID_PUBLISHER_BASE}/applications/${PACKAGE_NAME}` +
      `/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${accessTokenResponse.token}` },
    });

    if (response.status === 404) {
      console.warn(`Token not found: product=${productId}`);
      return { error: "token_not_found" };
    }

    if (response.status === 410) {
      console.warn(`Token expired: product=${productId}`);
      return { error: "token_expired" };
    }

    if (!response.ok) {
      const text = await response.text();
      console.error(`Play API error ${response.status}: ${text}`);
      return { error: "play_api_error" };
    }

    const data = await response.json() as PlayApiSubscription;
    return { data };
  } catch (e) {
    console.error("Exception calling Play API:", e);
    return { error: "exception" };
  }
}

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ valid: false, reason: "method_not_allowed" }, 405);
  }

  // Authenticate user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ valid: false, reason: "unauthenticated" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ valid: false, reason: "unauthenticated" }, 401);
  }

  // Parse request
  let body: VerifyRequest;
  try {
    body = await req.json() as VerifyRequest;
  } catch {
    return jsonResponse({ valid: false, reason: "invalid_request" }, 400);
  }

  const { purchase_token, product_id, plan_id } = body;

  if (!purchase_token || !product_id || !plan_id) {
    return jsonResponse({ valid: false, reason: "missing_fields" }, 400);
  }

  // Call Google Play Developer API
  const result = await callPlayApi(purchase_token, product_id);

  if (result.error) {
    return jsonResponse({ valid: false, reason: result.error });
  }

  const sub = result.data!;

  // paymentState: 0=pending, 1=received, 2=free trial, 3=pending deferred upgrade
  if (sub.paymentState !== 1 && sub.paymentState !== 2) {
    console.warn(`paymentState=${sub.paymentState} for user=${user.id}`);
    return jsonResponse({ valid: false, reason: "payment_not_received" });
  }

  // Expiry validation
  if (!sub.expiryTimeMillis) {
    return jsonResponse({ valid: false, reason: "no_expiry" });
  }

  const expiryMs = parseInt(sub.expiryTimeMillis, 10);
  if (isNaN(expiryMs)) {
    return jsonResponse({ valid: false, reason: "invalid_expiry" });
  }

  const now = Date.now();
  if (expiryMs <= now) {
    return jsonResponse({ valid: false, reason: "expired" });
  }

  // All validations passed
  const expiresAt = new Date(expiryMs).toISOString();

  console.log(
    `verify-receipt OK: user=${user.id}, product=${product_id}, ` +
      `plan=${plan_id}, expires=${expiresAt}, ` +
      `autoRenewing=${sub.autoRenewing}`,
  );

  return jsonResponse({
    valid: true,
    subscription: {
      product_id,
      expires_at: expiresAt,
      auto_renewing: sub.autoRenewing ?? false,
    },
  });
});