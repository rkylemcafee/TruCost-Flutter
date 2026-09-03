import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ============================================================
// state-fuel
// Returns per-state miles + gallons for a load, as structured JSON
// (so the app can render a Fuel-by-State panel). Same logic the
// co-pilot's get_state_fuel_burn uses: geocode each city, decode the
// route into per-state miles via trucost.app, split the empty deadhead
// (current location -> pickup) from the loaded haul (pickup -> delivery),
// and convert miles to gallons using the rig's empty/loaded MPG.
//
// Goes in: supabase/functions/state-fuel/index.ts
// Deploy:  supabase functions deploy state-fuel
// ============================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function geocodeOne(q: string): Promise<{ lat: number; lng: number } | null> {
  try {
    const res = await fetch("https://www.trucost.app/api/geocode", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ q, country: "US" }),
    });
    if (!res.ok) return null;
    const j = await res.json();
    if (typeof j.lat === "number" && typeof j.lng === "number") return { lat: j.lat, lng: j.lng };
    return null;
  } catch (_) {
    return null;
  }
}

async function stateMilesForLeg(origin: string, destination: string): Promise<Record<string, number> | null> {
  const o = await geocodeOne(origin);
  const d = await geocodeOne(destination);
  if (!o || !d) return null;
  try {
    const res = await fetch("https://www.trucost.app/api/google-route", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // originLabel / destLabel are the city names the driver typed. The route
      // cache keys on them ("louisville ky|miami fl") so the same lane is one
      // row no matter where in town each address geocoded to.
      body: JSON.stringify({
        origin: o,
        destination: d,
        originLabel: origin,
        destLabel: destination,
      }),
    });
    if (!res.ok) return null;
    const j = await res.json();
    const segs = Array.isArray(j.stateSegments) ? j.stateSegments : [];
    const states: Record<string, number> = {};
    for (const s of segs) {
      if (s && s.stateAbbr) states[s.stateAbbr] = (states[s.stateAbbr] || 0) + (Number(s.miles) || 0);
    }
    return states;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const body = await req.json();
    const pickup = (body.pickup || "").trim();
    const delivery = (body.delivery || "").trim();
    const current = (body.current_location || "").trim();

    if (!pickup || !delivery) {
      return new Response(
        JSON.stringify({ error: "pickup and delivery are required" }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    // MPG: request override -> active truck -> profile default (mirrors the co-pilot).
    const { data: { user } } = await supabase.auth.getUser();
    let pr: any = {};
    let truck: any = null;
    if (user) {
      const { data: prof } = await supabase
        .from("profiles")
        .select("empty_mpg, loaded_mpg, active_truck_id")
        .eq("user_id", user.id)
        .maybeSingle();
      pr = prof || {};
      if (pr.active_truck_id) {
        const { data } = await supabase.from("units").select("empty_mpg, loaded_mpg")
          .eq("id", pr.active_truck_id).is("deleted_at", null).maybeSingle();
        truck = data || null;
      }
      if (!truck) {
        const { data } = await supabase.from("units").select("empty_mpg, loaded_mpg")
          .eq("user_id", user.id).eq("unit_type", "truck").eq("is_active", true).is("deleted_at", null).limit(1);
        truck = data && data.length ? data[0] : null;
      }
    }
    const emptyMpg = body.empty_mpg != null ? parseFloat(body.empty_mpg)
      : (truck && truck.empty_mpg != null ? parseFloat(truck.empty_mpg) : (parseFloat(pr.empty_mpg) || 6));
    const loadedMpg = body.loaded_mpg != null ? parseFloat(body.loaded_mpg)
      : (truck && truck.loaded_mpg != null ? parseFloat(truck.loaded_mpg) : (parseFloat(pr.loaded_mpg) || 5));

    const milesByState: Record<string, number> = {};
    const galByState: Record<string, number> = {};

    // Empty deadhead leg: current location -> pickup (only if a start was given)
    let hasDeadhead = false;
    if (current) {
      const dh = await stateMilesForLeg(current, pickup);
      if (dh) {
        hasDeadhead = true;
        for (const [st, mi] of Object.entries(dh)) {
          milesByState[st] = (milesByState[st] || 0) + mi;
          galByState[st] = (galByState[st] || 0) + (emptyMpg > 0 ? mi / emptyMpg : 0);
        }
      }
    }

    // Loaded haul: pickup -> delivery
    const ld = await stateMilesForLeg(pickup, delivery);
    if (!ld) {
      return new Response(
        JSON.stringify({ error: "Couldn't pull the route — double-check the city names." }),
        { status: 422, headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }
    for (const [st, mi] of Object.entries(ld)) {
      milesByState[st] = (milesByState[st] || 0) + mi;
      galByState[st] = (galByState[st] || 0) + (loadedMpg > 0 ? mi / loadedMpg : 0);
    }

    const rows = Object.keys(milesByState)
      .map((st) => ({ state: st, miles: milesByState[st], gallons: galByState[st] }))
      .filter((r) => r.miles >= 1)
      .sort((a, b) => b.miles - a.miles);

    const totalMiles = rows.reduce((s, r) => s + r.miles, 0);
    const totalGallons = rows.reduce((s, r) => s + r.gallons, 0);

    return new Response(
      JSON.stringify({ rows, totalMiles, totalGallons, emptyMpg, loadedMpg, hasDeadhead }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  } catch (err) {
    console.error("state-fuel error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
