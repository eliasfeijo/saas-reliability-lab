import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush";

function convertVapidPublicKeyToJWK(publicKey: string) {
  // 1. Decode the base64 URL-safe string
  const padding = '='.repeat((4 - (publicKey.length % 4)) % 4);
  const base64 = (publicKey + padding)
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const binary = atob(base64);
  
  // 2. Extract the coordinates
  const prefix = binary.charCodeAt(0);
  if (prefix !== 4) {
    throw new Error('Invalid EC key format: expected uncompressed point (0x04 prefix)');
  }
  
  // Convert binary coordinates to base64
  const x = btoa(binary.substring(1, 33));
  const y = btoa(binary.substring(33, 65));
  
  // 3. Create properly formatted JWK
  return {
    kty: "EC",
    crv: "P-256",
    x: x.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''),
    y: y.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''),
    ext: true
  };
}

async function convertVapidKeysToCryptoKeyPair(publicKey: string, privateKey: string): Promise<CryptoKeyPair> {
  // Convert public key first (using our previous function)
  const publicJWK = convertVapidPublicKeyToJWK(publicKey);
  // Now add the private component
  const privateJWK = {
    ...publicJWK,
    d: privateKey // The private key is already in correct base64url format
  };
  const publicCryptoKey = await crypto.subtle.importKey(
    "jwk",
    { ...publicJWK, d: undefined }, // Public key only
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"]
  );
  const privateCryptoKey = await crypto.subtle.importKey(
    "jwk",
    privateJWK,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"]
  );
  return {
    publicKey: publicCryptoKey,
    privateKey: privateCryptoKey
  }
}

function getVapidKeys() {
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  if (!publicKey || !privateKey) {
    throw new Error("VAPID keys are not set in environment variables");
  }
  return convertVapidKeysToCryptoKeyPair(publicKey, privateKey);
}

interface Notification {
  id: string;
  title: string;
  notify_at: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Credentials": "true",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { 
      status: 405,
      headers: { ...corsHeaders }
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: notifications, error } = await supabase.rpc(
      "get_my_pending_notifications",
      { now: new Date().toISOString() }
    );

    if (error) throw error;
    if (!notifications?.length) {
      return new Response(
        JSON.stringify({ message: "No pending notifications" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize webpush with properly formatted keys
    const vapidKeys = await getVapidKeys();
    
    const appServer = await webpush.ApplicationServer.new({
      contactInformation: `mailto:${Deno.env.get("VAPID_CONTACT") || "admin@example.com"}`,
      vapidKeys,
    });

    const results = await Promise.allSettled(
      notifications.map(async (notif: Notification) => {
        try {
          const subscriber = appServer.subscribe({
            endpoint: notif.endpoint,
            keys: { p256dh: notif.p256dh, auth: notif.auth }
          });

          await subscriber.pushTextMessage(notif.title, {
            topic: "Task Reminder",
            ttl: 86400,
            urgency: webpush.Urgency.High
          });

          await supabase
            .from("tasks")
            .update({ notification_sent: true })
            .eq("id", notif.id);
        } catch (err) {
          console.error(`Failed to send notification ${notif.id}:`, err);
          throw err;
        }
      })
    );

    const failed = results.filter(r => r.status === "rejected").length;
    return new Response(
      JSON.stringify({
        success: true,
        sent: notifications.length - failed,
        failed
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("Error:", err);
    return new Response(
      JSON.stringify({ 
        error: "Internal server error",
        details: (err as Error).message 
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});