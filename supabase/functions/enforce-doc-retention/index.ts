import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ============================================================
// enforce-doc-retention
//
// Keeps a rolling window of the 3 most recently dated LOADS that
// have document images in Supabase Storage. Images come from two
// tables: expenses (receipts) and trip_documents (rate cons, BOLs,
// PODs, permits, other). When a 4th documented load appears, the
// OLDEST documented load's images are deleted from storage and
// their references are nulled.
//
// ONLY images are purged. Every number/text row stays in Postgres
// forever (so a report can still show "POD filed, ref #123" after
// the picture is gone — the picture lives on the phone).
//
// Call from the app right after a successful image upload.
//
// Goes in: supabase/functions/enforce-doc-retention/index.ts
// ============================================================

const KEEP = 3; // most-recent documented loads to keep images for

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    const authed = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await authed.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Not signed in" }), {
        status: 401,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // 1) Gather every load-linked image from BOTH sources.
    const pathsByTrip: Record<string, string[]> = {};

    const { data: receipts, error: rErr } = await admin
      .from("expenses")
      .select("trip_id, receipt_url")
      .eq("user_id", user.id)
      .not("trip_id", "is", null)
      .not("receipt_url", "is", null);
    if (rErr) throw rErr;
    for (const d of (receipts || [])) {
      const t = String(d.trip_id);
      (pathsByTrip[t] ||= []).push(d.receipt_url as string);
    }

    const { data: docs, error: dErr } = await admin
      .from("trip_documents")
      .select("trip_id, storage_path")
      .eq("user_id", user.id)
      .not("trip_id", "is", null)
      .not("storage_path", "is", null);
    if (dErr) throw dErr;
    for (const d of (docs || [])) {
      const t = String(d.trip_id);
      (pathsByTrip[t] ||= []).push(d.storage_path as string);
    }

    const tripIds = Object.keys(pathsByTrip);
    if (tripIds.length === 0) {
      return new Response(JSON.stringify({ kept: [], purged: [], deleted: 0 }), {
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // 2) Order those loads newest-first by load date.
    const { data: trips, error: tErr } = await admin
      .from("trips")
      .select("id, trip_date")
      .in("id", tripIds);
    if (tErr) throw tErr;

    const dateOf = (id: string): number => {
      const t = (trips || []).find((x) => String(x.id) === id);
      const d = t?.trip_date || null;
      return d ? new Date(d).getTime() : 0; // undated loads sort oldest
    };
    const ordered = [...tripIds].sort((a, b) => dateOf(b) - dateOf(a));

    const keep = ordered.slice(0, KEEP);
    const purge = ordered.slice(KEEP);

    if (purge.length === 0) {
      return new Response(JSON.stringify({ kept: keep, purged: [], deleted: 0 }), {
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // 3) For each load past the window: delete its images, null its refs.
    let deleted = 0;
    for (const t of purge) {
      const paths = (pathsByTrip[t] || []).filter(Boolean);
      if (paths.length) {
        const { error: rmErr } = await admin.storage.from("receipts").remove(paths);
        if (rmErr) console.error("remove error for trip", t, rmErr);
        else deleted += paths.length;
      }
      const { error: e1 } = await admin
        .from("expenses").update({ receipt_url: null })
        .eq("user_id", user.id).eq("trip_id", t);
      if (e1) console.error("null receipt_url error", t, e1);

      const { error: e2 } = await admin
        .from("trip_documents").update({ storage_path: null })
        .eq("user_id", user.id).eq("trip_id", t);
      if (e2) console.error("null storage_path error", t, e2);
    }

    return new Response(JSON.stringify({ kept: keep, purged: purge, deleted }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    console.error("enforce-doc-retention error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
