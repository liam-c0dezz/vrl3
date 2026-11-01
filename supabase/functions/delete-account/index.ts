import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function base64URL(value: string | Uint8Array): string {
  const bytes =
    typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}

function privateKeyBytes(pem: string): Uint8Array {
  const normalized = pem.replaceAll("\\n", "\n");
  const encoded = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(encoded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function makeAppleClientSecret(): Promise<{
  clientID: string;
  secret: string;
}> {
  const teamID = Deno.env.get("APPLE_TEAM_ID");
  const keyID = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  const clientID =
    Deno.env.get("APPLE_CLIENT_ID") ??
    "com.constructionestimate.Construction-Estimate";

  if (!teamID || !keyID || !privateKey) {
    throw new Error(
      "Apple revocation is not configured. Set APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, and APPLE_CLIENT_ID.",
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID }));
  const payload = base64URL(
    JSON.stringify({
      iss: teamID,
      iat: now,
      exp: now + 300,
      aud: "https://appleid.apple.com",
      sub: clientID,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKey).buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      cryptoKey,
      new TextEncoder().encode(signingInput),
    ),
  );

  return {
    clientID,
    secret: `${signingInput}.${base64URL(signature)}`,
  };
}

async function revokeAppleAuthorization(
  authorizationCode: string,
): Promise<void> {
  const { clientID, secret } = await makeAppleClientSecret();
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: secret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
    signal: AbortSignal.timeout(20_000),
  });
  const tokenPayload = await tokenResponse.json();
  if (!tokenResponse.ok) {
    console.error("Apple token exchange failed", tokenResponse.status);
    throw new Error("Apple could not confirm this account. Please try again.");
  }

  const token = tokenPayload.refresh_token ?? tokenPayload.access_token;
  if (typeof token !== "string" || token.length === 0) {
    throw new Error("Apple did not return a revocable authorization.");
  }

  const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: secret,
      token,
      token_type_hint: tokenPayload.refresh_token
        ? "refresh_token"
        : "access_token",
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (!revokeResponse.ok) {
    console.error(
      "Apple authorization revocation failed",
      revokeResponse.status,
    );
    throw new Error(
      "Apple authorization could not be revoked. Please try again.",
    );
  }
}

function hasAppleIdentity(user: {
  app_metadata?: Record<string, unknown>;
  identities?: Array<{ provider?: string }> | null;
}): boolean {
  const providers = user.app_metadata?.providers;
  return (
    user.app_metadata?.provider === "apple" ||
    (Array.isArray(providers) && providers.includes("apple")) ||
    user.identities?.some((identity) => identity.provider === "apple") === true
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const contentLength = Number(request.headers.get("Content-Length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > 16_384) {
      return jsonResponse({ error: "Request body is too large" }, 413);
    }

    const authorization = request.headers.get("Authorization");
    const accessToken = authorization?.replace(/^Bearer\s+/i, "");
    if (!accessToken) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseURL || !serviceRoleKey || !publicKey) {
      throw new Error("Supabase environment is not configured");
    }

    const admin = createClient(supabaseURL, serviceRoleKey);
    const { data: authData, error: authError } =
      await admin.auth.getUser(accessToken);
    if (authError || !authData.user) {
      return jsonResponse({ error: "Invalid or expired session" }, 401);
    }

    let body: Record<string, unknown>;
    try {
      const parsed = await request.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return jsonResponse({ error: "Invalid request body" }, 400);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return jsonResponse({ error: "Invalid request body" }, 400);
    }

    const appleLinked = hasAppleIdentity(authData.user);
    const authorizationCode = body.apple_authorization_code;
    const hasValidAppleAuthorizationCode =
      typeof authorizationCode === "string" &&
      authorizationCode.length > 0 &&
      authorizationCode.length <= 4096;

    const { data: ownedOrganizations, error: organizationsError } = await admin
      .from("organizations")
      .select("id")
      .eq("owner_user_id", authData.user.id);
    if (organizationsError) throw organizationsError;

    const organizationIDs = (ownedOrganizations ?? []).map((row) => row.id);
    if (organizationIDs.length > 0) {
      const { data: otherMembers, error: membersError } = await admin
        .from("organization_members")
        .select("user_id")
        .in("organization_id", organizationIDs)
        .neq("user_id", authData.user.id)
        .limit(1);
      if (membersError) throw membersError;
      if ((otherMembers ?? []).length > 0) {
        return jsonResponse(
          {
            error:
              "Transfer or remove the other organization members before deleting the owner account.",
            code: "organization_has_other_members",
          },
          409,
        );
      }
    }

    let appleAuthorizationRevoked = !appleLinked;
    if (appleLinked && hasValidAppleAuthorizationCode) {
      try {
        await revokeAppleAuthorization(authorizationCode as string);
        appleAuthorizationRevoked = true;
      } catch (error) {
        // Apple's account-deletion guidance requires the user's account data
        // to be deleted even when no revocable token is available. Keep the
        // deletion path reliable while logging enough to fix revocation
        // configuration without exposing provider response bodies.
        console.error(
          "Apple authorization could not be revoked; continuing account deletion",
          error instanceof Error ? error.message : "UnknownError",
        );
      }
    } else if (appleLinked) {
      console.error(
        "Apple authorization code unavailable; continuing account deletion",
      );
    }

    // Remove private objects first. The SQL transaction below then deletes all
    // relational rows and the auth identity. Exact paths come from metadata,
    // so deletion cannot escape this user's owned organizations.
    if (organizationIDs.length > 0) {
      const { data: documents, error: documentsError } = await admin
        .from("project_documents")
        .select("storage_path")
        .in("organization_id", organizationIDs);
      if (documentsError) throw documentsError;

      const paths = [
        ...new Set(
          (documents ?? [])
            .map((document) => document.storage_path)
            .filter(
              (path): path is string =>
                typeof path === "string" && path.length > 0,
            ),
        ),
      ];
      for (let index = 0; index < paths.length; index += 100) {
        const { error: removalError } = await admin.storage
          .from("project-files")
          .remove(paths.slice(index, index + 100));
        if (removalError) throw removalError;
      }
    }

    const userClient = createClient(supabaseURL, publicKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const { data: deleted, error: deletionError } = await userClient.rpc(
      "delete_current_user_account",
    );
    if (deletionError) throw deletionError;
    if (deleted !== true) {
      throw new Error("Account deletion did not complete");
    }

    return jsonResponse({
      deleted: true,
      apple_authorization_revoked: appleAuthorizationRevoked,
    });
  } catch (error) {
    // Do not write provider/database response bodies to logs.
    console.error(
      "Account deletion failed",
      error instanceof Error ? error.name : "UnknownError",
    );
    return jsonResponse(
      {
        error: [
          "Apple could not confirm this account. Please try again.",
          "Apple did not return a revocable authorization.",
          "Apple authorization could not be revoked. Please try again.",
        ].includes(error instanceof Error ? error.message : "")
          ? (error as Error).message
          : "Account deletion failed. Your account is still active.",
      },
      500,
    );
  }
});
