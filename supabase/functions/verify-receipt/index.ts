// verify-receipt Edge Function — REAL (Session 6) + Logging (Phase M4)
//
// Verifies Google Play subscription purchase tokens server-side.
// Logs invocations to edge_function_logs table (non-blocking).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PACKAGE_NAME = "com.usconnect.ezeebook";
const ANDROID_PUBLISHER_BASE =
  "https://androidpublisher.googleapis.com/androidpublisher/v3";
const FUNCTION_NAME = "verify-receipt";

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

// ============ INLINE LOGGER ============
// Fire-and-forget: never blocks main function; errors are silenced.
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
    // Fire-and-forget: NOT awaited
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
    // Never let logging crash the function
    console.error("log threw:", e);
  }
}

// Redact purchase token for logging (keep last 8 chars only)
function redactToken(token: string): string {
  if (!token || token.length < 12) return "***";
  return "***" + token.slice(-8);
}
// ============ END LOGGER ============

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
  const startTime = Date.now();
  const ipAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    log({
      level: "warn",
      message: "Method not allowed",
      metadata: { method: req.method },
      ipAddress,
      status: "method_not_allowed",
    });
    return jsonResponse({ valid: false, reason: "method_not_allowed" }, 405);
  }

  try {
    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      log({
        level: "warn",
        message: "Missing Authorization header",
        ipAddress,
        status: "unauthenticated",
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "unauthenticated" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      log({
        level: "warn",
        message: "Invalid JWT",
        ipAddress,
        status: "unauthenticated",
        metadata: { error: userError?.message ?? "no_user" },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "unauthenticated" }, 401);
    }

    // Parse request
    let body: VerifyRequest;
    try {
      body = await req.json() as VerifyRequest;
    } catch {
      log({
        level: "warn",
        message: "Invalid JSON body",
        userId: user.id,
        ipAddress,
        status: "invalid_request",
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "invalid_request" }, 400);
    }

    const { purchase_token, product_id, plan_id } = body;

    if (!purchase_token || !product_id || !plan_id) {
      log({
        level: "warn",
        message: "Missing required fields",
        userId: user.id,
        ipAddress,
        status: "missing_fields",
        metadata: {
          has_purchase_token: !!purchase_token,
          has_product_id: !!product_id,
          has_plan_id: !!plan_id,
        },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "missing_fields" }, 400);
    }

    // Log invocation with useful metadata
    log({
      level: "info",
      message: "verify-receipt invoked",
      userId: user.id,
      ipAddress,
      metadata: {
        product_id,
        plan_id,
        purchase_token_redacted: redactToken(purchase_token),
      },
    });

    // Call Google Play Developer API
    const result = await callPlayApi(purchase_token, product_id);

    if (result.error) {
      log({
        level: "warn",
        message: `Google Play API returned error: ${result.error}`,
        userId: user.id,
        ipAddress,
        status: result.error,
        metadata: { product_id, plan_id },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: result.error });
    }

    const sub = result.data!;

    // paymentState: 0=pending, 1=received, 2=free trial, 3=pending deferred upgrade
    if (sub.paymentState !== 1 && sub.paymentState !== 2) {
      log({
        level: "warn",
        message: "paymentState indicates payment not received",
        userId: user.id,
        ipAddress,
        status: "payment_not_received",
        metadata: { product_id, plan_id, paymentState: sub.paymentState },
        durationMs: Date.now() - startTime,
      });
      console.warn(`paymentState=${sub.paymentState} for user=${user.id}`);
      return jsonResponse({ valid: false, reason: "payment_not_received" });
    }

    // Expiry validation
    if (!sub.expiryTimeMillis) {
      log({
        level: "warn",
        message: "Missing expiryTimeMillis in Play API response",
        userId: user.id,
        ipAddress,
        status: "no_expiry",
        metadata: { product_id, plan_id },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "no_expiry" });
    }

    const expiryMs = parseInt(sub.expiryTimeMillis, 10);
    if (isNaN(expiryMs)) {
      log({
        level: "warn",
        message: "Invalid expiryTimeMillis",
        userId: user.id,
        ipAddress,
        status: "invalid_expiry",
        metadata: {
          product_id,
          plan_id,
          expiryTimeMillis: sub.expiryTimeMillis,
        },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "invalid_expiry" });
    }

    const now = Date.now();
    if (expiryMs <= now) {
      log({
        level: "warn",
        message: "Subscription already expired",
        userId: user.id,
        ipAddress,
        status: "expired",
        metadata: {
          product_id,
          plan_id,
          expires_at: new Date(expiryMs).toISOString(),
        },
        durationMs: Date.now() - startTime,
      });
      return jsonResponse({ valid: false, reason: "expired" });
    }

    // All validations passed
    const expiresAt = new Date(expiryMs).toISOString();

    log({
      level: "info",
      message: "Receipt verified successfully",
      userId: user.id,
      ipAddress,
      status: "success",
      metadata: {
        product_id,
        plan_id,
        expires_at: expiresAt,
        auto_renewing: sub.autoRenewing ?? false,
      },
      durationMs: Date.now() - startTime,
    });

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
  } catch (e) {
    // Uncaught exception — always logs
    const errorMessage = e instanceof Error ? e.message : String(e);
    const errorStack = e instanceof Error ? e.stack : undefined;
    log({
      level: "error",
      message: "Uncaught exception in verify-receipt",
      ipAddress,
      status: "exception",
      metadata: { error: errorMessage, stack: errorStack },
      durationMs: Date.now() - startTime,
    });
    console.error("verify-receipt uncaught:", e);
    return jsonResponse({ valid: false, reason: "exception" }, 500);
  }
});