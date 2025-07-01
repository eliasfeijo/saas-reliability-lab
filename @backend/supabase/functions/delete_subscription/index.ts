// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import { createClient } from "https://esm.sh/@supabase/supabase-js";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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
    return new Response("Method Not Allowed", { status: 405, headers: corsHeaders });
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      global: {
        headers: {
          Authorization: req.headers.get("Authorization")!,
        },
      },
    }
  );
  const { endpoint } = await req.json();
  if (!endpoint) {
    return new Response("Endpoint is required", { status: 400, headers: corsHeaders });
  }

  const { error } = await supabase
    .from("push_subscriptions")
    .delete()
    .eq("user_id", (await supabase.auth.getUser()).data.user?.id)
    .eq("endpoint", decodeURIComponent(endpoint));

  if (error) {
    return new Response(JSON.stringify({ error }), { status: 500, headers: corsHeaders });
  }

  return new Response("Unsubscribed", { status: 200, headers: corsHeaders});
});
