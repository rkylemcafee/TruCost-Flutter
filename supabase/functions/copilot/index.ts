import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const GOOGLE_MAPS_KEY = Deno.env.get("GOOGLE_MAPS_KEY");

const SYSTEM_PROMPT = `You are a voice assistant for owner-operator truck drivers.

Your personality:
- Talk like a fellow trucker, not a robot. Keep it real.
- Be concise — 2-3 sentences max unless they ask for detail.
- Use dollars, miles, and hours.
- If a load sounds bad, say so. If good, tell them to grab it.

Rules:
- When the driver mentions two cities, USE get_driving_distance to get exact miles. NEVER guess miles.
- If deadhead is separate from pickup, call the tool twice.
- You know the driver's MPG, fuel cost, carrier cut, and overhead — DO NOT ask for these.
- To price ANY load, USE price_load. NEVER do the dollar math in your head  it pulls the driver's ACTIVE truck and trailer, regional diesel, overhead, and carrier cut, and returns the real take-home and the real $/hr.
- The result's $/hr is take-home AFTER every cost. Compare it to the driver's target (it's in the result) and say it plain: "after everything you're at $43 an hour, a little under the $55 you want."
- The target is the driver's OWN number from the result  never assume $50.
- If a load comes up short, do NOT just say pass  find the lever. Fuel and the truck payment are fixed, but the deal isn't. Suggest asking the broker for detention pay (after the first hour loading and the first hour unloading), a better rate, or less deadhead  then call price_load AGAIN with that change (extra_pay for detention or a bonus, or fewer load_unload_hours) and tell them if it clears their bar. e.g. "If you get detention after the first hour each way, that's about $150 more  want me to see if it gets you there?"
- The driver also controls his SPEED and his MPG on a given run  he can push 70 on open highway instead of his default, or get better mileage on a light load. If he gives you new numbers, rerun price_load with empty_speed / loaded_speed and/or empty_mpg / loaded_mpg for that load.
- When you save a priced load, use the numbers price_load gave you.
- When the driver says to save a trip, USE save_trip with all the numbers you calculated.
- When saving a trip, ALWAYS include the contact_name if one was mentioned in the conversation. If no contact was mentioned, ask "Who offered this load?" before saving.
- Before saving any trip, you MUST know the driver's current location to calculate deadhead miles to the pickup. If the driver hasn't told you where they are, ASK: "Where are you located now? I'll figure the deadhead." Then use get_driving_distance from their location to the pickup.
- When the driver renegotiates a price on a saved trip, USE update_trip to update it — don't create a new one.
- When the driver wants to add or remove a state from a contact's good-load areas, or change any contact's info (company, phone, rating, type, notes), USE update_contact. Always use 2-letter state abbreviations (FL, GA, TX).
- The driver's full rig (every truck and trailer) is listed below under DRIVER'S RIG. Use it to answer questions about their equipment.
- When the driver wants to add a truck or trailer, USE add_unit. The rig is capped at 2 trucks and 3 trailers; if they're at the cap, say so and offer to remove one.
- When the driver wants to change a truck or trailer (price, payment, MPG, its number, or trailer type), USE update_unit and identify it by its number.
- When the driver wants to remove or delete a truck or trailer, USE delete_unit (a soft delete it can be brought back), identified by its number.
- When the driver wants to call someone, USE make_call to open the phone dialer.
- When the driver wants to text someone, USE send_text to open Messages.
- No markdown bold (**) in responses — this is for voice/mobile display.

Keep responses SHORT. No bullet points, no lists — talk naturally.`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const TOOLS = [
  {
    name: "get_driving_distance",
    description: "Get driving distance in miles between two locations via Google Maps.",
    input_schema: {
      type: "object",
      properties: {
        origin: { type: "string", description: "Starting city/address" },
        destination: { type: "string", description: "Ending city/address" },
      },
      required: ["origin", "destination"],
    },
  },
  {
    name: "save_trip",
    description: "Save a trip calculation to the driver's trip history in the database.",
    input_schema: {
      type: "object",
      properties: {
        trip_name: { type: "string", description: "Short name like 'Tampa to Houston'" },
        origin: { type: "string", description: "Pickup city/address" },
        destination: { type: "string", description: "Delivery city/address" },
        gross_pay: { type: "number", description: "Gross pay offered" },
        deadhead_miles: { type: "number", description: "Deadhead miles" },
        loaded_miles: { type: "number", description: "Loaded miles" },
        total_miles: { type: "number", description: "Total miles" },
        estimated_fuel_cost: { type: "number", description: "Estimated fuel cost" },
        estimated_net: { type: "number", description: "Estimated net profit to driver" },
        fuel_price_used: { type: "number", description: "Fuel price per gallon used" },
        contact_name: { type: "string", description: "Name of the contact/broker who offered this load, if known" },
      },
      required: ["trip_name", "origin", "destination", "gross_pay", "total_miles", "estimated_net"],
    },
  },
  {
    name: "update_trip",
    description: "Update an existing saved trip. Use when the driver negotiated a better rate or needs to change details on a recently saved trip.",
    input_schema: {
      type: "object",
      properties: {
        trip_name_search: { type: "string", description: "Part of the trip name to find, e.g. 'Tampa to Miami'" },
        gross_pay: { type: "number", description: "New gross pay amount" },
        estimated_net: { type: "number", description: "New estimated net profit" },
        estimated_fuel_cost: { type: "number", description: "New estimated fuel cost" },
          deadhead_miles: { type: "number", description: "New deadhead miles" },
                  loaded_miles: { type: "number", description: "New loaded miles" },
                  origin: { type: "string", description: "New pickup origin (driver's current location for deadhead)" },
      },
      required: ["trip_name_search"],
    },
  },
  {
    name: "update_contact",
    description: "Edit a saved contact. Add or remove the states where they have good loads, replace that whole list, or change their company, phone, email, city, state, type, rating, or notes. Finds the contact by name.",
    input_schema: {
      type: "object",
      properties: {
        contact_name: { type: "string", description: "Name (or part of the name) of the contact to edit" },
        add_states: { type: "array", items: { type: "string" }, description: "State abbreviations to ADD to their best-load states, e.g. ['FL','GA']" },
        remove_states: { type: "array", items: { type: "string" }, description: "State abbreviations to REMOVE from their best-load states" },
        best_load_states: { type: "array", items: { type: "string" }, description: "Replace the entire best-load-states list with exactly these abbreviations" },
        company: { type: "string" },
        phone: { type: "string" },
        email: { type: "string" },
        city: { type: "string" },
        state: { type: "string" },
        contact_type: { type: "string", description: "Direct Customer, Broker, Agent, or Escort" },
        star_rating: { type: "number", description: "0 to 5" },
        notes: { type: "string" },
      },
      required: ["contact_name"],
    },
  },
  {
    name: "send_text",
    description: "Send a text message to a contact. Use when the driver wants to reach out to a broker, agent, or customer.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Phone number to text" },
        message: { type: "string", description: "Text message to send" },
        contact_name: { type: "string", description: "Name of the contact" },
      },
      required: ["phone", "message"],
    },
  },
  {
    name: "make_call",
    description: "Open the phone dialer to call a contact. Use when the driver wants to call someone.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Phone number to call" },
        contact_name: { type: "string", description: "Name of the contact" },
      },
      required: ["phone"],
    },
  },
  {
    name: "add_unit",
    description: "Add a new truck or trailer to the driver's rig. Max 2 trucks and 3 trailers.",
    input_schema: {
      type: "object",
      properties: {
        unit_type: { type: "string", enum: ["truck", "trailer"], description: "truck or trailer" },
        unit_number: { type: "string", description: "Unit number, e.g. '1010' or '220'" },
        cost_mode: { type: "string", enum: ["owned", "financed"], description: "owned or financed" },
        purchase_price: { type: "number", description: "Purchase price if owned" },
        depreciation_pct: { type: "number", description: "Annual depreciation percent if owned, e.g. 20" },
        monthly_payment: { type: "number", description: "Monthly payment if financed" },
        empty_mpg: { type: "number", description: "Empty MPG (trucks only)" },
        loaded_mpg: { type: "number", description: "Loaded MPG (trucks only)" },
        trailer_subtype: { type: "string", description: "Trailer type (trailers only): flatbed, step_deck, double_drop, dry_van, reefer" },
      },
      required: ["unit_type"],
    },
  },
  {
    name: "update_unit",
    description: "Change an existing truck or trailer the driver already has. Identify it by unit_type and its unit_number.",
    input_schema: {
      type: "object",
      properties: {
        unit_type: { type: "string", enum: ["truck", "trailer"] },
        unit_number: { type: "string", description: "Which unit to change, by its current number" },
        new_unit_number: { type: "string", description: "New number, if renumbering it" },
        cost_mode: { type: "string", enum: ["owned", "financed"] },
        purchase_price: { type: "number" },
        depreciation_pct: { type: "number" },
        monthly_payment: { type: "number" },
        empty_mpg: { type: "number" },
        loaded_mpg: { type: "number" },
        trailer_subtype: { type: "string" },
      },
      required: ["unit_type", "unit_number"],
    },
  },
  {
    name: "delete_unit",
    description: "Remove a truck or trailer from the rig (soft delete  hidden, not destroyed). Identify by unit_type and unit_number.",
    input_schema: {
      type: "object",
      properties: {
        unit_type: { type: "string", enum: ["truck", "trailer"] },
        unit_number: { type: "string", description: "Which unit to remove, by its number" },
      },
      required: ["unit_type", "unit_number"],
    },
  },
  {
    name: "price_load",
    description: "Price a load with the driver's REAL costs  active truck + trailer, regional diesel, overhead, carrier cut. ALWAYS use this for net and $/hr; never compute them yourself. Call it again with adjusted inputs to run what-ifs (detention pay via extra_pay, a higher rate via gross_pay, or fewer load_unload_hours).",
    input_schema: {
      type: "object",
      properties: {
        gross_pay: { type: "number", description: "Line-haul gross the broker is offering" },
        loaded_miles: { type: "number", description: "Loaded miles, pickup to delivery" },
        deadhead_miles: { type: "number", description: "Empty miles to the pickup" },
        tolls_other: { type: "number", description: "Tolls or other out-of-pocket, if any" },
        load_unload_hours: { type: "number", description: "Total hours loading + unloading. Omit to use the driver's default." },
        extra_pay: { type: "number", description: "Extra revenue for a what-if  detention pay or a bonus, added on top of gross" },
        empty_speed: { type: "number", description: "Override empty (deadhead) speed mph for this run, e.g. 70 on open highway" },
        loaded_speed: { type: "number", description: "Override loaded speed mph for this run" },
        empty_mpg: { type: "number", description: "Override empty MPG for this run, e.g. better mileage on a light load" },
        loaded_mpg: { type: "number", description: "Override loaded MPG for this run" },
        pickup: { type: "string", description: "Pickup city/state, for regional fuel" },
        delivery: { type: "string", description: "Delivery city/state, for regional fuel" },
      },
      required: ["gross_pay", "loaded_miles"],
    },
  },
];

async function getDistance(origin: string, destination: string): Promise<string> {
  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&key=${GOOGLE_MAPS_KEY}`;
    const res = await fetch(url);
    const data = await res.json();
    if (data.status === "OK" && data.routes?.length > 0) {
      const meters = data.routes[0].legs[0].distance.value;
      const miles = Math.round(meters / 1609.34);
      const duration = data.routes[0].legs[0].duration.text;
      return `${miles} miles, approximately ${duration} driving time`;
    }
    return "Could not calculate distance";
  } catch (e) {
    return `Error: ${e}`;
  }
}

async function saveTrip(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const now = new Date();
    const datePfx = `${String(now.getMonth()+1).padStart(2,'0')}${String(now.getDate()).padStart(2,'0')}${now.getFullYear()}`;

    let contactId = null;
    if (input.contact_name) {
      const { data: contacts } = await supabase
        .from("contacts")
        .select("id, name")
        .eq("user_id", user.id)
        .ilike("name", `%${input.contact_name}%`)
        .limit(1);
      if (contacts && contacts.length > 0) {
        contactId = contacts[0].id;
      }
    }

    await supabase.from("trips").insert({
      user_id: user.id,
      trip_name: `${datePfx} - ${input.trip_name} - $${input.gross_pay}`,
      origin: input.origin || null,
      destination: input.destination || null,
      contact_id: contactId,
      gross_pay: input.gross_pay,
      deadhead_miles: input.deadhead_miles || 0,
      loaded_miles: input.loaded_miles || 0,
      estimated_fuel_cost: input.estimated_fuel_cost || 0,
      estimated_net: input.estimated_net || 0,
      fuel_price_used: input.fuel_price_used || 5.35,
      trip_date: now.toISOString().substring(0, 10),
      status: "saved",
      estimate_json: {
        grossPay: input.gross_pay,
        estimatedNet: input.estimated_net,
        estimatedFuel: input.estimated_fuel_cost,
        totalMiles: input.total_miles,
        source: "copilot",
      },
    });

    const contactNote = contactId ? ` under ${input.contact_name}` : (input.contact_name ? ` (could not find ${input.contact_name} in contacts)` : " with no contact attached");
    return `Trip saved${contactNote}: ${input.trip_name}, $${input.gross_pay} gross, ${input.total_miles} miles, net $${input.estimated_net}`;
  } catch (e) {
    return `Error saving trip: ${e}`;
  }
}

async function updateTrip(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: trips } = await supabase
      .from("trips")
      .select("id, trip_name, gross_pay")
      .eq("user_id", user.id)
      .ilike("trip_name", `%${input.trip_name_search}%`)
      .order("created_at", { ascending: false })
      .limit(1);

    if (!trips || trips.length === 0) {
      return `Could not find a trip matching "${input.trip_name_search}"`;
    }

    const trip = trips[0];
      const updates: any = {};
          if (input.gross_pay) updates.gross_pay = input.gross_pay;
          if (input.estimated_net) updates.estimated_net = input.estimated_net;
          if (input.estimated_fuel_cost) updates.estimated_fuel_cost = input.estimated_fuel_cost;
          if (input.deadhead_miles !== undefined) updates.deadhead_miles = input.deadhead_miles;
          if (input.loaded_miles !== undefined) updates.loaded_miles = input.loaded_miles;
          if (input.origin) updates.origin = input.origin;

    await supabase.from("trips").update(updates).eq("id", trip.id);

    return `Updated "${trip.trip_name}" — gross pay now $${input.gross_pay || trip.gross_pay}${input.estimated_net ? ', net $' + input.estimated_net : ''}`;
  } catch (e) {
    return `Error updating trip: ${e}`;
  }
}

function normState(s: string): string | null {
  const t = (s || "").trim();
  if (!t) return null;
  if (t.length === 2) return t.toUpperCase();
  return STATE_ABBR[t.toLowerCase()] ?? null;
}

const STATE_ABBR: Record<string, string> = {
  "alabama":"AL","arizona":"AZ","arkansas":"AR","california":"CA","colorado":"CO",
  "connecticut":"CT","delaware":"DE","florida":"FL","georgia":"GA","idaho":"ID",
  "illinois":"IL","indiana":"IN","iowa":"IA","kansas":"KS","kentucky":"KY",
  "louisiana":"LA","maine":"ME","maryland":"MD","massachusetts":"MA","michigan":"MI",
  "minnesota":"MN","mississippi":"MS","missouri":"MO","montana":"MT","nebraska":"NE",
  "nevada":"NV","new hampshire":"NH","new jersey":"NJ","new mexico":"NM","new york":"NY",
  "north carolina":"NC","north dakota":"ND","ohio":"OH","oklahoma":"OK","oregon":"OR",
  "pennsylvania":"PA","rhode island":"RI","south carolina":"SC","south dakota":"SD",
  "tennessee":"TN","texas":"TX","utah":"UT","vermont":"VT","virginia":"VA",
  "washington":"WA","west virginia":"WV","wisconsin":"WI","wyoming":"WY",
};

async function updateContact(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: matches } = await supabase
      .from("contacts")
      .select("id, name, best_load_states")
      .eq("user_id", user.id)
      .ilike("name", `%${input.contact_name}%`)
      .order("name")
      .limit(5);

    if (!matches || matches.length === 0) {
      return `Could not find a contact matching "${input.contact_name}".`;
    }
    const contact = matches[0];

    const updates: any = {};
    let current: string[] = Array.isArray(contact.best_load_states) ? [...contact.best_load_states] : [];
    let statesTouched = false;

    if (Array.isArray(input.best_load_states)) {
      current = input.best_load_states.map(normState).filter((x: string | null) => !!x) as string[];
      statesTouched = true;
    } else {
      if (Array.isArray(input.add_states)) {
        for (const raw of input.add_states) {
          const a = normState(raw);
          if (a && !current.includes(a)) current.push(a);
        }
        statesTouched = true;
      }
      if (Array.isArray(input.remove_states)) {
        const rm = (input.remove_states.map(normState).filter((x: string | null) => !!x)) as string[];
        current = current.filter((st) => !rm.includes(st));
        statesTouched = true;
      }
    }
    if (statesTouched) {
      current = Array.from(new Set(current)).sort();
      updates.best_load_states = current;
    }

    for (const f of ["company", "phone", "email", "city", "state", "contact_type", "notes"]) {
      if (input[f] !== undefined && input[f] !== null) updates[f] = input[f];
    }
    if (input.star_rating !== undefined && input.star_rating !== null) {
      updates.star_rating = input.star_rating;
    }

    if (Object.keys(updates).length === 0) {
      return `Nothing to change on ${contact.name}.`;
    }

    await supabase.from("contacts").update(updates).eq("id", contact.id);

    const statePart = statesTouched
      ? ` Best load states now: ${updates.best_load_states.length ? updates.best_load_states.join(", ") : "none"}.`
      : "";
    return `Updated ${contact.name}.${statePart}`;
  } catch (e) {
    return `Error updating contact: ${e}`;
  }
}

async function findUnit(supabase: any, userId: string, unitType: string, unitNumber: string) {
  const { data } = await supabase
    .from("units")
    .select("*")
    .eq("user_id", userId)
    .eq("unit_type", unitType)
    .is("deleted_at", null)
    .ilike("unit_number", `${unitNumber}`)
    .limit(1);
  return data && data.length > 0 ? data[0] : null;
}

async function addUnit(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";
    const type = input.unit_type === "trailer" ? "trailer" : "truck";
    const cap = type === "truck" ? 2 : 3;
    const { data: existing } = await supabase
      .from("units").select("id")
      .eq("user_id", user.id).eq("unit_type", type).is("deleted_at", null);
    const count = existing ? existing.length : 0;
    if (count >= cap) {
      return `Can't add  you're already at the max of ${cap} ${type}s. Remove one first if you want to swap.`;
    }
    const mode = input.cost_mode === "financed" ? "financed" : "owned";
    const row: any = {
      user_id: user.id,
      unit_type: type,
      unit_number: (input.unit_number || "").toString().trim(),
      cost_mode: mode,
      purchase_price: mode === "owned" ? (input.purchase_price ?? null) : null,
      depreciation_pct: mode === "owned" ? (input.depreciation_pct ?? 20) : null,
      monthly_payment: mode === "financed" ? (input.monthly_payment ?? null) : null,
      is_active: count === 0,
    };
    if (type === "truck") {
      row.empty_mpg = input.empty_mpg ?? null;
      row.loaded_mpg = input.loaded_mpg ?? null;
    } else {
      row.trailer_subtype = input.trailer_subtype || "flatbed";
    }
    const { data: inserted } = await supabase.from("units").insert(row).select("id").single();
    if (row.is_active && inserted) {
      const key = type === "truck" ? "active_truck_id" : "active_trailer_id";
      await supabase.from("profiles").update({ [key]: inserted.id }).eq("user_id", user.id);
    }
    const label = `${type === "truck" ? "truck" : (row.trailer_subtype || "trailer")} ${row.unit_number}`.trim();
    return `Added ${label}${row.is_active ? `, and set it as your active ${type}` : ""}.`;
  } catch (e) {
    return `Error adding unit: ${e}`;
  }
}

async function updateUnit(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";
    const type = input.unit_type === "trailer" ? "trailer" : "truck";
    const unit = await findUnit(supabase, user.id, type, (input.unit_number || "").toString().trim());
    if (!unit) return `Couldn't find ${type} ${input.unit_number} in your rig.`;
    const updates: any = {};
    if (input.new_unit_number !== undefined) updates.unit_number = input.new_unit_number.toString().trim();
    if (input.cost_mode) updates.cost_mode = input.cost_mode === "financed" ? "financed" : "owned";
    if (input.purchase_price !== undefined) updates.purchase_price = input.purchase_price;
    if (input.depreciation_pct !== undefined) updates.depreciation_pct = input.depreciation_pct;
    if (input.monthly_payment !== undefined) updates.monthly_payment = input.monthly_payment;
    if (type === "truck") {
      if (input.empty_mpg !== undefined) updates.empty_mpg = input.empty_mpg;
      if (input.loaded_mpg !== undefined) updates.loaded_mpg = input.loaded_mpg;
    } else {
      if (input.trailer_subtype) updates.trailer_subtype = input.trailer_subtype;
    }
    if (Object.keys(updates).length === 0) return `Nothing to change on ${type} ${input.unit_number}.`;
    await supabase.from("units").update(updates).eq("id", unit.id);
    return `Updated ${type} ${updates.unit_number || unit.unit_number}.`;
  } catch (e) {
    return `Error updating unit: ${e}`;
  }
}

async function deleteUnit(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";
    const type = input.unit_type === "trailer" ? "trailer" : "truck";
    const unit = await findUnit(supabase, user.id, type, (input.unit_number || "").toString().trim());
    if (!unit) return `Couldn't find ${type} ${input.unit_number} in your rig.`;
    await supabase.from("units")
      .update({ deleted_at: new Date().toISOString(), is_active: false })
      .eq("id", unit.id);
    const key = type === "truck" ? "active_truck_id" : "active_trailer_id";
    const { data: prof } = await supabase.from("profiles").select(key).eq("user_id", user.id).maybeSingle();
    if (prof && prof[key] === unit.id) {
      await supabase.from("profiles").update({ [key]: null }).eq("user_id", user.id);
    }
    return `Removed ${type} ${unit.unit_number} from your rig.`;
  } catch (e) {
    return `Error removing unit: ${e}`;
  }
}

const STATE_TO_PADD: Record<string,string> = {
  CT:'R1X',ME:'R1X',MA:'R1X',NH:'R1X',RI:'R1X',VT:'R1X',
  DE:'R1Y',DC:'R1Y',MD:'R1Y',NJ:'R1Y',NY:'R1Y',PA:'R1Y',
  FL:'R1Z',GA:'R1Z',NC:'R1Z',SC:'R1Z',VA:'R1Z',WV:'R1Z',
  IL:'R20',IN:'R20',IA:'R20',KS:'R20',KY:'R20',MI:'R20',
  MN:'R20',MO:'R20',NE:'R20',ND:'R20',OH:'R20',OK:'R20',
  SD:'R20',TN:'R20',WI:'R20',
  AL:'R30',AR:'R30',LA:'R30',MS:'R30',NM:'R30',TX:'R30',
  CO:'R40',ID:'R40',MT:'R40',UT:'R40',WY:'R40',
  AK:'R50',AZ:'R50',HI:'R50',NV:'R50',OR:'R50',WA:'R50',
  CA:'R5XCA',
};
const PADD_FALLBACK: Record<string,string> = { R1X:'R10', R1Y:'R10', R1Z:'R10', R5XCA:'R50' };

function extractState(addr: string): string | null {
  if (!addr) return null;
  const m = addr.match(/,\s*([A-Za-z]{2})\b/);
  if (m) return m[1].toUpperCase();
  const words = addr.trim().split(/\s+/);
  if (words.length && words[words.length - 1].length === 2) return words[words.length - 1].toUpperCase();
  return null;
}

async function loadRegionalPrices(supabase: any): Promise<{ prices: Record<string,number>, nat: number }> {
  const prices: Record<string,number> = {};
  let nat = 5.35;
  try {
    const { data: rows } = await supabase
      .from("fuel_cache_regions")
      .select("region_code, price")
      .eq("cache_id", "eia-diesel-weekly")
      .order("fetched_at", { ascending: false });
    if (rows) {
      for (const r of rows) {
        const code = (r.region_code ?? "").toString();
        const price = parseFloat((r.price ?? "").toString());
        if (code && !(code in prices) && !isNaN(price)) prices[code] = price;
      }
    }
    if (prices["NUS"]) nat = prices["NUS"];
  } catch (_) { /* fall back to nat */ }
  return { prices, nat };
}

function priceForState(state: string, prices: Record<string,number>, nat: number): number {
  const region = STATE_TO_PADD[state.toUpperCase()];
  if (region && prices[region] !== undefined) return prices[region];
  if (region) {
    const parent = PADD_FALLBACK[region];
    if (parent && prices[parent] !== undefined) return prices[parent];
  }
  return nat;
}

function fuelForRoute(pickup: string, delivery: string, prices: Record<string,number>, nat: number): number {
  const ps = extractState(pickup || "");
  const ds = extractState(delivery || "");
  const prg = ps ? STATE_TO_PADD[ps] : null;
  const drg = ds ? STATE_TO_PADD[ds] : null;
  if (prg && prg === drg && ps) return priceForState(ps, prices, nat);
  const pp = prg ? (PADD_FALLBACK[prg] ?? prg) : null;
  const dp2 = drg ? (PADD_FALLBACK[drg] ?? drg) : null;
  if (pp && pp === dp2) {
    const p1 = ps ? priceForState(ps, prices, nat) : nat;
    const p2 = ds ? priceForState(ds, prices, nat) : nat;
    return (p1 + p2) / 2;
  }
  return nat;
}

// Mirrors trucost_engine.dart  take-home model, no driver wage subtracted.
function computeLoad(p: any) {
  const deadhead = Math.max(0, p.deadhead || 0);
  const loaded = Math.max(0, p.loaded || 0);
  const totalMiles = deadhead + loaded;

  const emptyDriveHours = deadhead / Math.max(1, p.emptySpeed || 60);
  const loadedDriveHours = loaded / Math.max(1, p.loadedSpeed || 55);
  const loadUnload = Math.max(0, p.loadUnloadHours ?? 8);
  const totalHours = emptyDriveHours + loadedDriveHours + loadUnload;

  const emptyFuel = (deadhead / Math.max(0.1, p.emptyMpg || 6)) * (p.fuelPrice || 5.35);
  const loadedFuel = (loaded / Math.max(0.1, p.loadedMpg || 5)) * (p.fuelPrice || 5.35);
  const totalFuel = emptyFuel + loadedFuel;

  const annualHours = (p.annualHours && p.annualHours > 0) ? p.annualHours : 2500;
  const hoursFraction = totalHours / annualHours;
  const equipment = ((p.truckAnnual || 0) + (p.trailerAnnual || 0)) * hoursFraction;

  const tolls = Math.max(0, p.tolls || 0);
  const baseCosts = totalFuel + equipment + tolls;
  const overhead = baseCosts * Math.max(0, p.overheadPct || 0);
  const totalCosts = baseCosts + overhead;

  const operatorShare = 1 - (p.carrierCutPct || 0);
  const gross = p.gross || 0;
  const operatorGross = gross * operatorShare;
  const net = operatorGross - totalCosts;
  const perHour = totalHours > 0 ? net / totalHours : 0;

  const target = p.target || 0;
  const minNet = totalCosts + target * totalHours;
  const minGross = operatorShare > 0 ? minNet / operatorShare : minNet;

  return {
    totalMiles, totalHours, totalFuel, equipment, overhead, totalCosts,
    carrierCut: gross * (p.carrierCutPct || 0), operatorGross, net, perHour,
    target, minGross, winner: perHour >= target,
  };
}

async function priceLoad(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: prof } = await supabase
      .from("profiles")
      .select("carrier_cut_pct, overhead_pct, hourly_rate, annual_work_hours, speed_empty, speed_loaded, empty_mpg, loaded_mpg, fuel_price_default, active_truck_id, active_trailer_id")
      .eq("user_id", user.id).maybeSingle();
    const pr = prof || {};

    async function activeUnit(type: string, pointerId: any) {
      if (pointerId) {
        const { data } = await supabase.from("units").select("*").eq("id", pointerId).is("deleted_at", null).maybeSingle();
        if (data) return data;
      }
      const { data } = await supabase.from("units").select("*")
        .eq("user_id", user.id).eq("unit_type", type).eq("is_active", true).is("deleted_at", null).limit(1);
      return data && data.length ? data[0] : null;
    }
    const truck = await activeUnit("truck", pr.active_truck_id);
    const trailer = await activeUnit("trailer", pr.active_trailer_id);

    const annualCost = (u: any) => {
      if (!u) return 0;
      if (u.cost_mode === "financed") return (parseFloat(u.monthly_payment) || 0) * 12;
      return (parseFloat(u.purchase_price) || 0) * ((parseFloat(u.depreciation_pct) || 20) / 100);
    };

    let fuelPrice = parseFloat(pr.fuel_price_default) || 5.35;
    if (input.pickup || input.delivery) {
      const { prices, nat } = await loadRegionalPrices(supabase);
      fuelPrice = fuelForRoute(input.pickup || "", input.delivery || "", prices, nat);
    }

    const emptyMpg = input.empty_mpg != null
        ? parseFloat(input.empty_mpg)
        : (truck && truck.empty_mpg != null ? parseFloat(truck.empty_mpg) : (parseFloat(pr.empty_mpg) || 6));
    const loadedMpg = input.loaded_mpg != null
        ? parseFloat(input.loaded_mpg)
        : (truck && truck.loaded_mpg != null ? parseFloat(truck.loaded_mpg) : (parseFloat(pr.loaded_mpg) || 5));

    const gross = (parseFloat(input.gross_pay) || 0) + (parseFloat(input.extra_pay) || 0);

    const r = computeLoad({
      gross,
      deadhead: parseFloat(input.deadhead_miles) || 0,
      loaded: parseFloat(input.loaded_miles) || 0,
      tolls: parseFloat(input.tolls_other) || 0,
      loadUnloadHours: input.load_unload_hours != null ? parseFloat(input.load_unload_hours) : 8,
      emptyMpg, loadedMpg,
      emptySpeed: input.empty_speed != null ? parseFloat(input.empty_speed) : (parseFloat(pr.speed_empty) || 60),
      loadedSpeed: input.loaded_speed != null ? parseFloat(input.loaded_speed) : (parseFloat(pr.speed_loaded) || 55),
      fuelPrice,
      target: parseFloat(pr.hourly_rate) || 0,
      truckAnnual: annualCost(truck),
      trailerAnnual: annualCost(trailer),
      carrierCutPct: (parseFloat(pr.carrier_cut_pct) || 0) / 100,
      overheadPct: (parseFloat(pr.overhead_pct) || 0) / 100,
      annualHours: parseFloat(pr.annual_work_hours) || 2500,
    });

    const f = (n: number) => `$${n.toFixed(2)}`;
    const truckLbl = truck ? `truck ${truck.unit_number || ""}`.trim() : "no active truck";
    const trailerLbl = trailer ? `${trailer.trailer_subtype || "trailer"} ${trailer.unit_number || ""}`.trim() : "no active trailer";
    return [
      "RESULT (real take-home, all costs in):",
      `- ${r.totalMiles.toFixed(0)} mi over ${r.totalHours.toFixed(1)} hrs, fuel @ ${f(fuelPrice)}/gal`,
      `- fuel ${f(r.totalFuel)}, equipment ${f(r.equipment)} (${truckLbl} + ${trailerLbl}), overhead ${f(r.overhead)}`,
      `- carrier cut ${f(r.carrierCut)}, your gross ${f(r.operatorGross)}`,
      `- NET take-home ${f(r.net)} = ${f(r.perHour)}/hr`,
      `- target ${f(r.target)}/hr -> ${r.winner ? "MET" : "SHORT"}`,
      `- to hit target, gross would need to be ${f(r.minGross)}`,
    ].join("\n");
  } catch (e) {
    return `Error pricing load: ${e}`;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
      const { message, history, driverName, copilotName, profile: driverProfile, session_id } = await req.json();

    if (!message) {
      return new Response(JSON.stringify({ error: "message required" }), {
        status: 400, headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
      // Get current user for message logging
          const { data: { user: currentUser } } = await supabase.auth.getUser();

          // Log user message
          if (currentUser && session_id) {
            try {
              await supabase.from("copilot_messages").insert({
                user_id: currentUser.id,
                session_id,
                role: "user",
                content: message,
              });
            } catch (e) { console.error("Log user msg failed:", e); }
          }

    let tripContext = "";
    try {
      const { data: trips } = await supabase
        .from("trips")
        .select("trip_name, origin, destination, gross_pay, estimated_net, estimated_fuel_cost, total_miles, deadhead_miles, loaded_miles, fuel_price_used, trip_date, estimate_json, contacts(name, company, phone)")
        .order("trip_date", { ascending: false })
        .limit(20);

      if (trips && trips.length > 0) {
        const tripLines = trips.map((t: any) => {
          const ej = t.estimate_json || {};
          const hourly = ej.effectiveHourlyRate ? `$${ej.effectiveHourlyRate.toFixed(2)}/hr` : "n/a";
          const winner = (t.estimated_net || 0) >= 0 ? "WINNER" : "LOSER";
          const contact = t.contacts ? `Contact: ${t.contacts.name}${t.contacts.company ? ' @ ' + t.contacts.company : ''}${t.contacts.phone ? ' Ph: ' + t.contacts.phone : ''}` : "No contact";
          return `- ${t.trip_date} | ${t.trip_name || "unnamed"} | ${t.origin || "?"} to ${t.destination || "?"} | ${t.total_miles}mi | Gross: $${t.gross_pay} | Net: $${(t.estimated_net || 0).toFixed ? t.estimated_net.toFixed(2) : t.estimated_net} | ${hourly} | ${winner} | ${contact}`;
        });
        tripContext = `\n\nDRIVER'S SAVED TRIPS:\n${tripLines.join("\n")}`;
      }
    } catch (e) {
      console.error("Trip query error:", e);
    }

    let fleetContext = "";
    try {
      if (currentUser) {
        const { data: units } = await supabase
          .from("units")
          .select("unit_type, unit_number, cost_mode, purchase_price, depreciation_pct, monthly_payment, empty_mpg, loaded_mpg, trailer_subtype, is_active")
          .eq("user_id", currentUser.id)
          .is("deleted_at", null);
        if (units && units.length > 0) {
          const lines = units.map((u: any) => {
            const cost = u.cost_mode === "financed"
              ? `$${u.monthly_payment}/mo`
              : `$${u.purchase_price} owned @ ${u.depreciation_pct || 20}%/yr`;
            const mpg = u.unit_type === "truck" ? `, ${u.empty_mpg ?? "?"}/${u.loaded_mpg ?? "?"} mpg` : "";
            const sub = u.unit_type === "trailer" && u.trailer_subtype ? ` ${u.trailer_subtype}` : "";
            const active = u.is_active ? " [ACTIVE]" : "";
            return `- ${u.unit_type}${sub} #${u.unit_number || "?"}: ${cost}${mpg}${active}`;
          });
          fleetContext = `\n\nDRIVER'S RIG (trucks & trailers):\n${lines.join("\n")}`;
        }
      }
    } catch (e) {
      console.error("Fleet query error:", e);
    }

    const dp = driverProfile || {};
    const nameContext = `\n\nDRIVER'S NAME: ${driverName || "driver"}\nYOUR NAME: ${copilotName || "Co-Pilot"}. That is your name — answer to it naturally. If the driver calls you by a nickname or a slightly different name, just roll with it; never correct them or insist you are called something else.\n\nDRIVER'S EQUIPMENT: Carrier cut ${dp.carrier_cut_pct || 25}%, Overhead ${dp.overhead_pct || 15}%, Fuel $${dp.fuel_price_default || 5.35}/gal, MPG ${dp.empty_mpg || 6}empty/${dp.loaded_mpg || 5}loaded, Target $${dp.hourly_rate || 50}/hr`;

    const fullSystem = SYSTEM_PROMPT + nameContext + tripContext + fleetContext;

    const messages: Array<{ role: string; content: any }> = [];
    if (Array.isArray(history)) {
      for (const h of history) {
        if (h.role && h.content) messages.push({ role: h.role, content: h.content });
      }
    }
    messages.push({ role: "user", content: message });

    const actions: Array<any> = [];

    let response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 500,
        system: fullSystem,
        messages,
        tools: TOOLS,
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("Anthropic error:", response.status, errText);
      return new Response(JSON.stringify({ error: "Claude API error" }), {
        status: 502, headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    let data = await response.json();

    let loops = 0;
    while (data.stop_reason === "tool_use" && loops < 6) {
      loops++;
      const toolBlocks = data.content.filter((b: any) => b.type === "tool_use");
      const toolResults: Array<any> = [];

      for (const tool of toolBlocks) {
        let result = "";
        if (tool.name === "get_driving_distance") {
          result = await getDistance(tool.input.origin, tool.input.destination);
        } else if (tool.name === "save_trip") {
          result = await saveTrip(supabase, tool.input);
        } else if (tool.name === "update_trip") {
          result = await updateTrip(supabase, tool.input);
        } else if (tool.name === "update_contact") {
          result = await updateContact(supabase, tool.input);
        } else if (tool.name === "add_unit") {
          result = await addUnit(supabase, tool.input);
        } else if (tool.name === "update_unit") {
          result = await updateUnit(supabase, tool.input);
        } else if (tool.name === "delete_unit") {
          result = await deleteUnit(supabase, tool.input);
        } else if (tool.name === "price_load") {
          result = await priceLoad(supabase, tool.input);
        } else if (tool.name === "send_text") {
          actions.push({ type: "sms", phone: tool.input.phone, body: tool.input.message, contact_name: tool.input.contact_name || "" });
          result = `Text message queued for ${tool.input.contact_name || tool.input.phone}.`;
        } else if (tool.name === "make_call") {
          actions.push({ type: "call", phone: tool.input.phone, contact_name: tool.input.contact_name || "" });
          result = `Phone dialer opening for ${tool.input.contact_name || tool.input.phone}.`;
        }
        toolResults.push({ type: "tool_result", tool_use_id: tool.id, content: result });
      }

      messages.push({ role: "assistant", content: data.content });
      messages.push({ role: "user", content: toolResults });

      response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": ANTHROPIC_API_KEY!,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 500,
          system: fullSystem,
          messages,
          tools: TOOLS,
        }),
      });

      data = await response.json();
    }

    const textBlocks = data.content?.filter((b: any) => b.type === "text") || [];
    const reply = textBlocks.map((b: any) => b.text).join("\n") || "Sorry, didn't catch that.";
      // Log assistant reply
          if (currentUser && session_id) {
            try {
              await supabase.from("copilot_messages").insert({
                user_id: currentUser.id,
                session_id,
                role: "assistant",
                content: reply,
                actions: actions.length > 0 ? actions : null,
              });
            } catch (e) { console.error("Log assistant msg failed:", e); }
          }

    return new Response(JSON.stringify({ reply, actions }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    console.error("Copilot error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
