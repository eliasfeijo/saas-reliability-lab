import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush";

// Helper function to convert raw VAPID keys to CryptoKeyPair
async function createVapidKeyPair(
  publicKey: string,
  privateKey: string
): Promise<CryptoKeyPair> {
  const publicKeyBytes = Uint8Array.from(atob(publicKey), (c) =>
    c.charCodeAt(0)
  );
  const privateKeyBytes = Uint8Array.from(atob(privateKey), (c) =>
    c.charCodeAt(0)
  );

  const [publicCryptoKey, privateCryptoKey] = await Promise.all([
    crypto.subtle.importKey(
      "raw",
      publicKeyBytes,
      { name: "ECDH", namedCurve: "P-256" },
      true,
      []
    ),
    crypto.subtle.importKey(
      "pkcs8",
      privateKeyBytes,
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign"]
    ),
  ]);

  return { publicKey: publicCryptoKey, privateKey: privateCryptoKey };
}

// Define the structure of a notification
interface Notification {
  id: string;
  title: string;
  user_id: string;
  notify_at: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

// CORS headers for preflight requests
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Credentials": "true",
};

Deno.serve(async (req) => {
  // Handle preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...corsHeaders,
      },
    });
  }
  // Only allow POST requests to save subscription
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    // 1. Authenticate the request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    // 2. Get pending notifications for this user
    const { data: notifications, error } = await supabase.rpc(
      "get_my_pending_notifications",
      { now: new Date().toISOString() }
    );

    if (error) throw error;
    if (!notifications?.length) {
      return new Response(
        JSON.stringify({ message: "No pending notifications" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        }
      );
    }

    // 3. Prepare webpush application server
    const vapidKeys = await createVapidKeyPair(
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const appServer = await webpush.ApplicationServer.new({
      contactInformation: `mailto:${
        Deno.env.get("VAPID_CONTACT") || "your-email@example.com"
      }`,
      vapidKeys,
    });

    // 4. Send notifications
    const results = await Promise.allSettled(
      (notifications as Notification[]).map(async (notification) => {
        try {
          const subscriber = appServer.subscribe({
            endpoint: notification.endpoint,
            keys: {
              p256dh: notification.p256dh,
              auth: notification.auth,
            },
          });

          await subscriber.pushTextMessage(`⏰ ${notification.title}`, {
            topic: "Task Reminder",
            ttl: 900,
            urgency: webpush.Urgency.High,
          });

          // Mark as sent if successful
          await supabase
            .from("tasks")
            .update({ notification_sent: true })
            .eq("id", notification.id);
        } catch (err) {
          console.error(`Failed to send notification ${notification.id}:`, err);
          throw err;
        }
      })
    );

    // 5. Handle results
    const failedCount = results.filter((r) => r.status === "rejected").length;

    return new Response(
      JSON.stringify({
        success: true,
        sent: notifications.length - failedCount,
        failed: failedCount,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  } catch (err) {
    console.error("Error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: (err as Error).message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  }
});
