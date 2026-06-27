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
- THERE IS ONE SAVE TOOL: save_load. Every load you price gets saved with it — there is no separate "save trip" anymore. When the driver says to save, record, log, or "put down" a load ("save it", "save this", "save it under [name]", "save that quote"), USE save_load.
- save_load runs the real engine itself and writes a COMPLETE record — fuel, hours, cost, net, and $/hr all filled in. Do NOT pass it your own cost numbers; give it the locations, the contact, and (only if the driver named one) the gross. It returns the real numbers; speak those. NEVER say it saved unless the tool returned a line starting with "Saved"; if a tool returns a line starting with "Error", tell the driver it did NOT save.
- A saved load is a QUOTE by default. The one thing you can't guess is whether it's just a quote or a load he's actually running. So when he asks to save and hasn't told you which, ASK once, plainly: "Want me to keep this as a quote, or are we running this one?" If it's a quote or a price for someone, call save_load with stage 'quote'. If he's running it / booked it / "we're doing this one", call save_load with stage 'won'. If he already told you which, don't ask — just save.
- If the broker put a number on the table first, pass it as offer_gross. Always pass contact_name when a customer or broker is named ("under Gertrude" -> contact_name "Gertrude"). Have the loaded miles (and deadhead, if a current location was given) first — from get_driving_distance, or let save_load look them up.
- To CHANGE anything on a saved load — the route (origin/destination), the rate, the stage, assign a contact, or add pickup/broker/pro/BOL numbers or notes — USE update_trip. Stages are: 'quote' (default), 'sent', 'won', 'booked', 'lost'. To assign/attach a contact to a load, pass assign_contact_name (e.g. driver says "assign Gertrude to this load" -> assign_contact_name "Gertrude"). To FIND the load you're changing, pass whatever the driver gives — and NUMBERS are the surest lock: if the driver reads off a broker number, pro number, or pickup number, pass it as match_broker_number / match_pro_number / match_pickup_number. The gross and route words also help. If you JUST pulled a load up with get_load and the driver says "change this one" / "assign her to this one", reuse what identified it (its gross, route, or a number) so update_trip lands on the same load. If update_trip returns a numbered LIST, read it and ask which, then call again with the gross or a number. NEVER tell the driver to go edit it in the app themselves — you can make the change; if a tool returns "Error", tell them plainly it didn't save.
- To READ BACK saved loads without changing anything ("pull up the Houston to Butte load", "what was the gross on that", "who's the broker", "what's the pickup number", "do I have a quote for Tampa to Houston"), USE get_load. It searches ALL the driver's loads across every stage. If it returns a numbered LIST (several matched), read that list to the driver and ask which one, then call get_load again with that load's gross or contact to pull full details. Use get_load to ANSWER questions about saved loads; only use update_trip when actually CHANGING one.
- The driver will toss out load details mid-conversation — a pickup or confirmation number, a broker/TQL number, a BOL number, a gate code, who to ask for at the dock, timing ("be there by 8"). NEVER pry for these, but whenever one is volunteered, SAVE it on the load: pickup_number, broker_number, and bol_number go in their own fields; anything else with no field of its own goes in notes (it appends, so nothing is lost). Use save_load if you're saving the load now, or update_trip to add details to a load already saved. You can read these back from the load's saved info to answer the driver later (e.g. "who am I asking for?" -> from notes).
- When the driver wants to add or remove a state from a contact's good-load areas, or change any contact's info (company, phone, rating, type, notes), USE update_contact. Always use 2-letter state abbreviations (FL, GA, TX).
- The driver's full rig (every truck and trailer) is listed below under DRIVER'S RIG. Use it to answer questions about their equipment.
- When the driver wants to add a truck or trailer, USE add_unit. The rig is capped at 2 trucks and 3 trailers; if they're at the cap, say so and offer to remove one.
- When the driver wants to change a truck or trailer (price, payment, MPG, its number, or trailer type), USE update_unit and identify it by its number.
- When the driver wants to remove or delete a truck or trailer, USE delete_unit (a soft delete it can be brought back), identified by its number.
- When the driver wants to call someone, USE make_call to open the phone dialer.
- When the driver wants to text someone, USE send_text to open Messages.
- When the driver wants to email someone, USE send_email to open their mail app. Write a clear subject and a short, professional body — you can speak the draft out loud first so the driver can okay it. Use the contact's saved email from the CONTACTS list below; if they have no email on file, ask the driver for it.
- Separately from the driver's personal CONTACTS, there's a shared BROKER DIRECTORY below — the big national broker and heavy-haul desks any driver can cold-call to find a load. When the driver asks who they can call, who's got freight, or who to try for a load, pull from this directory. They ALL run nationwide, so NEVER rank them by state or imply one is "better in New York" — what separates them is FREIGHT TYPE. Lead with that: for flatbed, oversize, heavy, or project loads point them to the heavy/specialized desks (Landstar, Bennett, ATS, Mercer); for plain van or reefer, any of them work. Some entries are a booking PORTAL, not a phone line (e.g. "EchoDrive portal", "RXO Connect", "Navisphere", "FreightPower") — for those, tell the driver to book through that portal and do NOT try to dial it. To reach a real number, USE make_call or send_email with the directory's dispatch_phone/email.
- There is ALSO an AGENT DIRECTORY: individual people (names + phone numbers), NOT companies — agents curated for the driver. When the driver asks who they can call or text for a load, who handles a certain freight type, who runs teams, or who's good for a lane/state, USE query_agents to search it (by freight type, trailer, origin state, team, or insurance fit). When they ask what's new ("any new agents this week?", "what got added lately?"), USE whats_new_agents. Both return REAL matches from the database — read back the names and numbers, never guess; agents the driver has hidden won't come back. To actually call or text one, USE make_call or send_text with the number query_agents returned.
- When the driver wants to ADD an agent to their personal contacts ("add Marcus", "keep Dana", "put that one in my contacts"), USE add_agent_to_contacts. After that the agent is a normal contact they can call, text, and edit.
- When the driver wants to HIDE or cull agents in bulk ("get rid of all the west-coast ones", "kill anything that needs teams", "I only want flatbed agents"), USE dismiss_agents. ALWAYS preview first: call it WITHOUT confirm to get the count and names, tell the driver "that's N agents — want me to hide them?", and only call again with confirm=true after they say yes. For "only keep X", set keep_only=true (that hides everything that ISN'T X). It is fully reversible — let them know you can bring any back.
- When the driver wants hidden agents back ("unhide the west coast ones", "bring them all back"), USE restore_agents.
- The driver can ask how many gallons they'll burn in each state (for IFTA, or to decide where to fuel), OR whether they've already bought enough fuel in a state. ONLY if they ask about fuel-by-state, gallons per state, IFTA, where/how much to fill, or "have I bought enough in [state]", USE get_state_fuel_burn with their current location (deadhead start), pickup, and delivery. NEVER bring this up on your own — it's noise to most drivers. It splits the empty deadhead from the loaded haul, so have their current location if you can; if you don't, ask once, but you can still run it on the loaded haul alone. The tool now also reports how many gallons they've ALREADY bought in each state (from their logged fuel receipts) and whether each state is covered or short — use that to answer "did I buy enough" directly instead of asking them how much they pumped.
- When the driver asks what you'd run a load for, a good price on it, or what they should quote ("what should I quote", "what's a good price on this", "what would you run this load for?"), ASK for the pickup and dropoff city + state if not already known from context. Once you have the two locations, call get_driving_distance for exact miles (and deadhead if they give a current location), then USE recommend_quote with pickup, delivery (and deadhead_miles or current_location). It uses the exact same TruCostEngine logic as the app's calculator to get real costs for the driver's active rig + regional fuel + overhead + carrier cut, then adds a profit margin above the driver's own target $/hr.
- ALWAYS give them BOTH numbers from recommend_quote: the gross to OPEN with, AND their FLOOR — the lowest gross that still holds their target $/hr. The floor is their walk-away so they can negotiate on the phone without calling you back. Say it plain, e.g. "I'd open at $4,725 on that Tampa to Houston run. If they push back, your floor's about $4,250 — below that you slip under your $50 an hour." Never give just the open number on its own.
- Reminder: recommend_quote just SAYS a price out loud; save_load COMPUTES and SAVES it (a quote by default). Saving is always save_load — there is no other save tool.
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
    name: "recommend_quote",
    description: "Calculate a recommended gross pay to quote the broker (or what you'd run a load for) using the driver's real TruCostEngine costs for their active truck+trailer, regional diesel, overhead and carrier cut, plus a solid profit margin above the driver's target hourly rate. Call this (after getting locations via get_driving_distance or conversation) when the driver asks what price to quote, what's a good price, or what you'd run this load for.",
    input_schema: {
      type: "object",
      properties: {
        pickup: { type: "string", description: "Pickup city and state, e.g. 'Memphis, TN'" },
        delivery: { type: "string", description: "Delivery city and state, e.g. 'Dallas, TX'" },
        deadhead_miles: { type: "number", description: "Deadhead miles to the pickup (use 0 or omit if at the pickup or unknown)" },
        load_unload_hours: { type: "number", description: "Total hours for loading + unloading (uses driver default ~8 if omitted)" },
        tolls_other: { type: "number", description: "Tolls or other out-of-pocket costs" },
        current_location: { type: "string", description: "Driver's current city/state if you need to calculate deadhead separately" },
      },
      required: ["pickup", "delivery"],
    },
  },
  {
    name: "save_load",
    description: "Compute AND save a load. This is the ONE save tool — there is no separate save-trip. It runs the real TruCostEngine math itself (active rig, regional diesel, overhead, carrier cut) and writes a complete record, so do NOT pass it your own cost numbers. Every priced load is saved with this. It defaults to a QUOTE (stage 'quote'); pass stage 'won' only if the driver clearly said they're running/booking it. Returns the real gross, net, and $/hr.",
    input_schema: {
      type: "object",
      properties: {
        pickup: { type: "string", description: "Pickup city and state, e.g. 'Tampa, FL'" },
        delivery: { type: "string", description: "Delivery city and state, e.g. 'Houston, TX'" },
        deadhead_miles: { type: "number", description: "Deadhead miles to the pickup (0 or omit if at the pickup or unknown)" },
        current_location: { type: "string", description: "Driver's current city/state, used to figure deadhead if deadhead_miles isn't given" },
        loaded_miles: { type: "number", description: "Loaded miles if already known from get_driving_distance (otherwise it looks them up)" },
        load_unload_hours: { type: "number", description: "Total hours for loading + unloading (uses driver default ~8 if omitted)" },
        tolls_other: { type: "number", description: "Tolls or other out-of-pocket costs" },
        quoted_gross: { type: "number", description: "The gross to quote/save IF the driver named a specific price. Omit to use the recommended price (the driver's target plus a buffer)." },
        offer_gross: { type: "number", description: "What the broker OFFERED, if they put a number on the table first." },
        margin_pct: { type: "number", description: "Optional percent to pad above the break-even floor instead of the default buffer." },
        stage: { type: "string", description: "'quote' (default) for a price you're giving someone; 'won' only if the driver clearly said they're running/booking this load." },
        contact_name: { type: "string", description: "The customer or broker this load is for, e.g. 'Gertrude'" },
        quote_name: { type: "string", description: "Optional custom label for the load" },
        pickup_number: { type: "string", description: "Pickup or confirmation number, if given." },
        broker_number: { type: "string", description: "Broker's load/confirmation number (TQL#), if given." },
        bol_number: { type: "string", description: "Bill of Lading number, if given." },
        notes: { type: "string", description: "Any loose detail volunteered with no field of its own (gate codes, who to ask for, timing, special instructions)." },
      },
      required: ["pickup", "delivery"],
    },
  },
  {
    name: "update_trip",
    description: "Update an existing saved load — change the route (origin/destination), rate, stage (quote/sent/won/booked/lost), assign a contact/broker to it, or add details (pickup/broker/pro/BOL numbers, notes). FIND the load by passing any combination you have: route words, gross, contact name, OR a broker_number/pro_number/pickup_number the driver reads off. Numbers are the surest match. If the driver just pulled a load up and says 'this one', pass whatever identified it (gross + route, or a number). If several loads still match, this returns a numbered LIST — read it and ask which, then call again with the gross or a number to lock it.",
    input_schema: {
      type: "object",
      properties: {
        trip_name_search: { type: "string", description: "Any words from the load's name, route, or contact, e.g. 'Houston Butte' or 'Gertrude'" },
        gross: { type: "number", description: "The load's gross/agreed price (e.g. 10000) — a strong way to pinpoint the right load." },
        contact_name: { type: "string", description: "Broker/customer currently ON the load, to help FIND it (not to assign — use assign_contact_name for that)." },
        match_broker_number: { type: "string", description: "Broker/confirmation number the driver reads off to FIND the load (e.g. 'TEST123')." },
        match_pro_number: { type: "string", description: "Pro number the driver reads off to FIND the load (e.g. '20260005')." },
        match_pickup_number: { type: "string", description: "Pickup number the driver reads off to FIND the load." },
        assign_contact_name: { type: "string", description: "Assign/attach a contact to this load by name (e.g. 'assign Gertrude' -> 'Gertrude'). Looks the name up in the driver's contacts and links it." },
        destination: { type: "string", description: "New delivery city/state, e.g. change 'Butte, MT' to 'Billings, MT'." },
        origin: { type: "string", description: "New pickup origin/city." },
        gross_pay: { type: "number", description: "New gross pay amount" },
        agreed_gross: { type: "number", description: "Final agreed price when the load is won/booked" },
        stage: { type: "string", description: "New stage: 'quote', 'sent', 'won', 'booked', or 'lost'." },
        estimated_net: { type: "number", description: "New estimated net profit" },
        estimated_fuel_cost: { type: "number", description: "New estimated fuel cost" },
        deadhead_miles: { type: "number", description: "New deadhead miles" },
        loaded_miles: { type: "number", description: "New loaded miles" },
        pickup_number: { type: "string", description: "SET the pickup/confirmation number on the load." },
        broker_number: { type: "string", description: "SET the broker's load/confirmation number on the load." },
        pro_number: { type: "string", description: "SET the pro number on the load." },
        bol_number: { type: "string", description: "SET the Bill of Lading number on the load." },
        notes: { type: "string", description: "Any loose detail with no field of its own (gate codes, who to ask for, timing). Appended to notes." },
      },
      required: [],
    },
  },
  {
    name: "get_load",
    description: "Look up the driver's saved loads and READ them back WITHOUT changing anything. Use whenever the driver asks about loads they've saved — 'pull up the Houston to Butte load', 'what was the gross on the Gertrude load', 'do I have a quote for Tampa to Houston', \'who\'s the broker on that\', 'what's the pickup number'. Searches across ALL stages (quote, sent, won, booked, lost). If several loads match, this returns a SHORT NUMBERED LIST — read the list back to the driver and ask which one they mean, then call get_load again with more detail (the gross or contact) to pull the full record. If exactly one matches, it returns that load's full details. Read back what it returns; never guess.",
    input_schema: {
      type: "object",
      properties: {
        trip_name_search: { type: "string", description: "Any words from the load's route, name, or contact, e.g. 'Houston Butte' or 'Tampa Houston'" },
        contact_name: { type: "string", description: "Broker/customer name if the driver names one" },
        gross: { type: "number", description: "The load's gross dollars if mentioned — strongest signal to pinpoint one load" },
        stage: { type: "string", description: "Optionally narrow by stage: 'quote', 'sent', 'won', 'booked', or 'lost'. Omit to search all." },
      },
      required: [],
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
    name: "send_email",
    description: "Open the driver's mail app with a drafted email to a contact. Use when the driver wants to email a broker, agent, or customer.",
    input_schema: {
      type: "object",
      properties: {
        email: { type: "string", description: "Recipient email address" },
        subject: { type: "string", description: "Email subject line" },
        body: { type: "string", description: "Email body text" },
        contact_name: { type: "string", description: "Name of the contact" },
      },
      required: ["email", "subject", "body"],
    },
  },
  {
    name: "get_state_fuel_burn",
    description: "Break a trip into miles and gallons burned per state. ONLY use when the driver explicitly asks about fuel by state, gallons per state, IFTA, or where/how much to fuel. NEVER volunteer it. Splits the empty deadhead (current location to pickup) from the loaded haul (pickup to delivery), using empty MPG and loaded MPG.",
    input_schema: {
      type: "object",
      properties: {
        current_location: { type: "string", description: "Driver's current location — start of the empty deadhead to the pickup. Include whenever known." },
        pickup: { type: "string", description: "Load pickup city/address" },
        delivery: { type: "string", description: "Load delivery city/address" },
        empty_mpg: { type: "number", description: "Override empty MPG for this run" },
        loaded_mpg: { type: "number", description: "Override loaded MPG for this run" },
      },
      required: ["pickup", "delivery"],
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
  {
    name: "query_agents",
    description: "Search the AGENT DIRECTORY (individual people/agents, NOT the broker companies) for ones that fit the driver's need. Use when they ask who to call/text for a load, who handles a freight type, who runs teams, who's good for a lane/state, or who fits their insurance. Returns real matches; agents the driver has hidden are excluded. Call with no filters to list everything available.",
    input_schema: {
      type: "object",
      properties: {
        freight_type: { type: "string", description: "Freight they want, e.g. 'flatbed', 'reefer', 'van', 'oversize'" },
        trailer_type: { type: "string", description: "Trailer needed, e.g. 'flatbed', 'step deck', 'RGN', 'reefer', 'van'" },
        origin_state: { type: "string", description: "A single 2-letter state the load comes OUT of, e.g. 'CA'" },
        origin_states: { type: "array", items: { type: "string" }, description: "Several states at once, e.g. a region like ['CA','OR','WA'] for the west coast" },
        team: { type: "boolean", description: "true to only return agents whose loads typically need a team" },
        within_my_insurance: { type: "boolean", description: "true to only return agents whose required cargo insurance is at or below what the driver carries" },
      },
      required: [],
    },
  },
  {
    name: "whats_new_agents",
    description: "List agents recently added to the directory. Use when the driver asks what's new, what agents got added this week or lately, etc. Excludes agents the driver has hidden.",
    input_schema: {
      type: "object",
      properties: {
        days: { type: "number", description: "How many days back to look. Default 7." },
      },
      required: [],
    },
  },
  {
    name: "add_agent_to_contacts",
    description: "Add an agent from the directory into the driver's personal contacts. Use when they say to add/keep/save a specific agent ('add Marcus', 'keep Dana', 'put that one in my contacts'). After this the agent is a normal contact they can call, text, and edit.",
    input_schema: {
      type: "object",
      properties: {
        agent_name: { type: "string", description: "Name (or part of the name) of the agent to add" },
      },
      required: ["agent_name"],
    },
  },
  {
    name: "dismiss_agents",
    description: "Hide one or more directory agents from the driver in bulk (soft, reversible). Use for culls like 'get rid of all the west-coast ones', 'kill anything that needs teams', or 'I only want flatbed agents'. ALWAYS call once WITHOUT confirm first to preview the count and names, get the driver's OK, then call again with confirm=true. Filters work the same as query_agents.",
    input_schema: {
      type: "object",
      properties: {
        freight_type: { type: "string", description: "Match agents with this freight type" },
        trailer_type: { type: "string", description: "Match agents with this trailer type" },
        origin_state: { type: "string", description: "A single 2-letter state the load comes OUT of, e.g. 'CA'" },
        origin_states: { type: "array", items: { type: "string" }, description: "Several states for a region cull, e.g. ['CA','OR','WA'] for the west coast" },
        team: { type: "boolean", description: "Match agents whose loads typically need a team" },
        within_my_insurance: { type: "boolean", description: "Match agents whose required insurance is at/below the driver's coverage" },
        keep_only: { type: "boolean", description: "If true, hide everything that does NOT match (i.e. KEEP ONLY the matches)" },
        confirm: { type: "boolean", description: "Leave false/absent to preview. Set true to actually hide, after the driver confirms." },
      },
      required: [],
    },
  },
  {
    name: "restore_agents",
    description: "Un-hide agents the driver previously dismissed. Use when they say 'bring them back', 'unhide the west coast ones', etc.",
    input_schema: {
      type: "object",
      properties: {
        agent_name: { type: "string", description: "Name (or part) of a hidden agent to bring back" },
        all: { type: "boolean", description: "true to restore ALL hidden agents" },
      },
      required: [],
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

async function getMiles(origin: string, destination: string): Promise<number> {
  const str = await getDistance(origin, destination);
  const match = str.match(/(\d+)\s*miles/i);
  return match ? parseInt(match[1]) : 0;
}

// ── Per-state fuel burn ───────────────────────────────────────────────────────
// Reuses trucost-web's existing server endpoints: /api/geocode turns a city into
// coords, /api/google-route returns per-state miles (it decodes the route polyline
// against the web's state-boundary data — same logic the permit mileage uses).

async function geocodeOne(q: string): Promise<{ lat: number; lng: number } | null> {
  try {
    const res = await fetch("https://trucost.app/api/geocode", {
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
    const res = await fetch("https://trucost.app/api/google-route", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ origin: o, destination: d }),
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

async function getStateFuelBurn(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    // MPG resolution mirrors price_load: input override → active truck → profile default.
    const { data: prof } = await supabase
      .from("profiles")
      .select("empty_mpg, loaded_mpg, active_truck_id")
      .eq("user_id", user.id).maybeSingle();
    const pr = prof || {};
    let truck: any = null;
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
    const emptyMpg = input.empty_mpg != null ? parseFloat(input.empty_mpg)
      : (truck && truck.empty_mpg != null ? parseFloat(truck.empty_mpg) : (parseFloat(pr.empty_mpg) || 6));
    const loadedMpg = input.loaded_mpg != null ? parseFloat(input.loaded_mpg)
      : (truck && truck.loaded_mpg != null ? parseFloat(truck.loaded_mpg) : (parseFloat(pr.loaded_mpg) || 5));

    const pickup = (input.pickup || "").trim();
    const delivery = (input.delivery || "").trim();
    const current = (input.current_location || "").trim();
    if (!pickup || !delivery) return "Need a pickup and a delivery to figure the per-state burn.";

    const milesByState: Record<string, number> = {};
    const galByState: Record<string, number> = {};

    // Deadhead leg (empty): current location → pickup
    if (current) {
      const dh = await stateMilesForLeg(current, pickup);
      if (dh) {
        for (const [st, mi] of Object.entries(dh)) {
          milesByState[st] = (milesByState[st] || 0) + mi;
          galByState[st] = (galByState[st] || 0) + (emptyMpg > 0 ? mi / emptyMpg : 0);
        }
      }
    }

    // Loaded leg: pickup → delivery
    const ld = await stateMilesForLeg(pickup, delivery);
    if (!ld) return "Couldn't pull the route for that trip — double-check the city names.";
    for (const [st, mi] of Object.entries(ld)) {
      milesByState[st] = (milesByState[st] || 0) + mi;
      galByState[st] = (galByState[st] || 0) + (loadedMpg > 0 ? mi / loadedMpg : 0);
    }

    // What the driver has ALREADY bought in each state on this load, so we can
    // answer "have I bought enough fuel for FL?" — not just what they'll burn.
    // Resolve the load by its route (most recent match) and total fuel gallons
    // by purchase state.
    const boughtByState: Record<string, number> = {};
    try {
      const pCity = pickup.split(",")[0].trim();
      const dCity = delivery.split(",")[0].trim();
      const { data: trip } = await supabase
        .from("trips")
        .select("id")
        .eq("user_id", user.id)
        .ilike("origin", `%${pCity}%`)
        .ilike("destination", `%${dCity}%`)
        .order("trip_date", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (trip && trip.id) {
        const { data: fuel } = await supabase
          .from("expenses")
          .select("gallons, purchase_state, category")
          .eq("user_id", user.id)
          .eq("trip_id", trip.id)
          .not("purchase_state", "is", null);
        for (const e of (fuel || [])) {
          const cat = String(e.category || "").toLowerCase();
          if (!cat.includes("fuel") && !cat.includes("def") && !cat.includes("diesel")) continue;
          const st = String(e.purchase_state).toUpperCase();
          boughtByState[st] = (boughtByState[st] || 0) + (parseFloat(e.gallons) || 0);
        }
      }
    } catch (_) { /* no purchases resolved — fall back to burn only */ }
    const hasBought = Object.keys(boughtByState).length > 0;

    const rows = Object.keys(milesByState)
      .map((st) => ({ st, miles: milesByState[st], gal: galByState[st] }))
      .filter((r) => r.miles >= 1)
      .sort((a, b) => b.miles - a.miles);
    if (rows.length === 0) return "No state mileage came back for that route.";

    const totMiles = rows.reduce((s, r) => s + r.miles, 0);
    const totGal = rows.reduce((s, r) => s + r.gal, 0);
    const lines = rows.map((r) => {
      const burn = Math.round(r.gal);
      if (!hasBought) return `${r.st}: ${Math.round(r.miles)} mi, ${burn} gal to burn`;
      const bought = Math.round(boughtByState[r.st] || 0);
      const diff = bought - burn;
      const status = diff >= 0 ? `covered (${diff} gal to spare)` : `SHORT ${Math.abs(diff)} gal`;
      return `${r.st}: burn ~${burn} gal, bought ${bought} gal — ${status}`;
    });
    const note = current
      ? `deadhead at ${emptyMpg} mpg empty, haul at ${loadedMpg} mpg loaded`
      : `haul only at ${loadedMpg} mpg loaded — no deadhead given`;
    const boughtNote = hasBought
      ? `\n("bought" is what's logged on this load's fuel receipts by state.)`
      : `\n(No fuel receipts with a state are logged on this load yet, so this is burn only.)`;
    return `Fuel by state (${note}):\n${lines.join("\n")}\nTotal: ${Math.round(totMiles)} mi, ${Math.round(totGal)} gal to burn.${boughtNote}`;
  } catch (e) {
    return `Error figuring fuel burn: ${e}`;
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

async function getLoad(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: allTrips } = await supabase
      .from("trips")
      .select("id, trip_name, gross_pay, agreed_gross, offer_gross, quoted_gross, origin, destination, stage, estimate_json, notes, pickup_number, broker_number, bol_number, pro_number, deadhead_miles, loaded_miles, net_to_operator, effective_hourly, contact_id, contacts(name), created_at")
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(60);

    let candidates: any[] = allTrips || [];

    if (input.stage) {
      const st = String(input.stage).toLowerCase();
      const hit = candidates.filter((t: any) => String(t.stage || "").toLowerCase() === st);
      if (hit.length) candidates = hit;
    }
    if (input.gross != null) {
      const g = Number(input.gross);
      const near = (v: any) => v != null && Math.abs(Number(v) - g) < 1;
      const hit = candidates.filter((t: any) =>
        near(t.gross_pay) || near(t.agreed_gross) || near(t.offer_gross) || near(t.quoted_gross));
      if (hit.length) candidates = hit;
    }
    if (input.contact_name) {
      const cn = String(input.contact_name).toLowerCase();
      const hit = candidates.filter((t: any) => t.contacts && String(t.contacts.name || "").toLowerCase().includes(cn));
      if (hit.length) candidates = hit;
    }
    if (input.trip_name_search) {
      const stop = ["the", "to", "and", "load", "run", "for", "from", "a", "on", "my"];
      const words = String(input.trip_name_search).toLowerCase().split(/\s+/).filter((w: string) => w.length > 1 && !stop.includes(w));
      if (words.length) {
        const hay = (t: any) => `${t.trip_name || ""} ${t.origin || ""} ${t.destination || ""} ${t.contacts ? t.contacts.name : ""}`.toLowerCase();
        const strict = candidates.filter((t: any) => words.every((w: string) => hay(t).includes(w)));
        if (strict.length) candidates = strict;
        else {
          const loose = candidates.filter((t: any) => words.some((w: string) => hay(t).includes(w.slice(0, 4))));
          if (loose.length) candidates = loose;
        }
      }
    }

    const f = (n: any) => `$${Math.round(Number(n) || 0)}`;
    const stageLabel = (s: string) => {
      const v = (s || "quote").toLowerCase();
      if (v === "booked") return "BOOKED";
      if (v === "won") return "won";
      if (v === "lost") return "lost";
      if (v === "sent") return "quote sent";
      return "quote";
    };

    if (candidates.length === 0) {
      const recent = (allTrips || []).slice(0, 6)
        .map((t: any) => `"${t.origin} to ${t.destination}" (${f(t.agreed_gross || t.gross_pay || t.quoted_gross)}, ${stageLabel(t.stage)})`).join("; ");
      return `No saved load matches that. Recent loads: ${recent || "none saved yet"}.`;
    }

    if (candidates.length > 1) {
      const list = candidates.slice(0, 6).map((t: any, i: number) => {
        const g = t.agreed_gross || t.gross_pay || t.quoted_gross || t.offer_gross;
        const who = t.contacts ? `, ${t.contacts.name}` : "";
        return `${i + 1}) ${t.origin} to ${t.destination} — ${f(g)} (${stageLabel(t.stage)})${who}`;
      }).join("; ");
      return `Found ${candidates.length} loads that match. Read these back and ask which one: ${list}. Then call get_load again with the gross or contact to pull that one's full details.`;
    }

    const t = candidates[0];
    const ej: any = t.estimate_json || {};
    const gross = t.agreed_gross || t.gross_pay || t.quoted_gross || t.offer_gross;
    const net = t.net_to_operator ?? ej.netToOperator ?? ej.netAtQuote;
    const perHr = t.effective_hourly ?? ej.effectiveHourlyRate;
    const broker = t.contacts ? t.contacts.name : null;

    const parts: string[] = [];
    parts.push(`${t.origin} to ${t.destination}`);
    parts.push(`${stageLabel(t.stage)}`);
    parts.push(`gross ${f(gross)}`);
    if (net != null) parts.push(`net ${f(net)}${perHr != null ? ` (~${f(perHr)}/hr)` : ""}`);
    if (t.loaded_miles) parts.push(`${Math.round(Number(t.loaded_miles))} loaded mi${t.deadhead_miles ? ` + ${Math.round(Number(t.deadhead_miles))} deadhead` : ""}`);
    if (broker) parts.push(`broker/contact: ${broker}`);
    else if (t.broker_number) parts.push(`broker #: ${t.broker_number}`);
    if (t.pro_number) parts.push(`pro #: ${t.pro_number}`);
    if (t.pickup_number) parts.push(`pickup #: ${t.pickup_number}`);
    if (t.bol_number) parts.push(`BOL #: ${t.bol_number}`);
    if (t.notes) parts.push(`notes: ${t.notes}`);
    if (!broker && !t.broker_number) parts.push(`(no broker saved on this load)`);

    return parts.join(" — ");
  } catch (e) {
    return `Error reading load: ${e}`;
  }
}

async function updateTrip(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: allTrips } = await supabase
      .from("trips")
      .select("id, trip_name, gross_pay, agreed_gross, offer_gross, quoted_gross, origin, destination, stage, estimate_json, notes, pickup_number, broker_number, pro_number, bol_number, contact_id, contacts(name), created_at")
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(60);

    let candidates: any[] = allTrips || [];

    // Numbers are the surest match — if the driver read one off, use it first.
    const numEq = (a: any, b: any) => a != null && b != null &&
      String(a).replace(/\D/g, "") === String(b).replace(/\D/g, "") && String(a).replace(/\D/g, "") !== "";
    if (input.match_broker_number) {
      const hit = candidates.filter((t: any) => numEq(t.broker_number, input.match_broker_number) ||
        String(t.broker_number || "").toLowerCase() === String(input.match_broker_number).toLowerCase());
      if (hit.length) candidates = hit;
    }
    if (input.match_pro_number) {
      const hit = candidates.filter((t: any) => numEq(t.pro_number, input.match_pro_number));
      if (hit.length) candidates = hit;
    }
    if (input.match_pickup_number) {
      const hit = candidates.filter((t: any) => numEq(t.pickup_number, input.match_pickup_number));
      if (hit.length) candidates = hit;
    }
    // Gross
    if (input.gross != null) {
      const g = Number(input.gross);
      const near = (v: any) => v != null && Math.abs(Number(v) - g) < 1;
      const hit = candidates.filter((t: any) =>
        near(t.gross_pay) || near(t.agreed_gross) || near(t.offer_gross) || near(t.quoted_gross));
      if (hit.length) candidates = hit;
    }
    // Contact currently on the load
    if (input.contact_name) {
      const cn = String(input.contact_name).toLowerCase();
      const hit = candidates.filter((t: any) => t.contacts && String(t.contacts.name || "").toLowerCase().includes(cn));
      if (hit.length) candidates = hit;
    }
    // Free-text route/name — strict, then loose fallback (handles 'Butte' vs stored 'Butt').
    if (input.trip_name_search) {
      const stop = ["the", "to", "and", "load", "run", "for", "from", "a", "on", "my", "this"];
      const words = String(input.trip_name_search).toLowerCase().split(/\s+/).filter((w: string) => w.length > 1 && !stop.includes(w));
      if (words.length) {
        const hay = (t: any) => `${t.trip_name || ""} ${t.origin || ""} ${t.destination || ""} ${t.contacts ? t.contacts.name : ""}`.toLowerCase();
        const strict = candidates.filter((t: any) => words.every((w: string) => hay(t).includes(w)));
        if (strict.length) candidates = strict;
        else {
          const loose = candidates.filter((t: any) => words.some((w: string) => hay(t).includes(w.slice(0, 4))));
          if (loose.length) candidates = loose;
        }
      }
    }

    const f = (n: any) => `$${Math.round(Number(n) || 0)}`;
    const stageLabel = (s: string) => {
      const v = (s || "quote").toLowerCase();
      if (v === "booked") return "BOOKED"; if (v === "won") return "won";
      if (v === "lost") return "lost"; if (v === "sent") return "quote sent"; return "quote";
    };

    if (candidates.length === 0) {
      const recent = (allTrips || []).slice(0, 6)
        .map((t: any) => `${t.origin} to ${t.destination} (${f(t.agreed_gross || t.gross_pay)}, ${stageLabel(t.stage)})`).join("; ");
      return `Error: could not find that load to update. Recent loads: ${recent || "none saved yet"}.`;
    }
    // Ambiguous — make Bob confirm instead of editing the wrong one.
    if (candidates.length > 1) {
      const list = candidates.slice(0, 6).map((t: any, i: number) =>
        `${i + 1}) ${t.origin} to ${t.destination} — ${f(t.agreed_gross || t.gross_pay)} (${stageLabel(t.stage)})`).join("; ");
      return `Found ${candidates.length} loads that match — read these back and ask which one before changing anything: ${list}. Then call update_trip again with the gross or a number to lock onto the right one.`;
    }

    const trip = candidates[0];

    // ---- Resolve a contact to ASSIGN, if asked ----
    let assignedContactId: string | null = null;
    let assignNote = "";
    if (input.assign_contact_name) {
      const { data: contacts } = await supabase
        .from("contacts")
        .select("id, name")
        .eq("user_id", user.id)
        .ilike("name", `%${input.assign_contact_name}%`)
        .limit(1);
      if (contacts && contacts.length > 0) {
        assignedContactId = contacts[0].id;
        assignNote = `, assigned ${contacts[0].name}`;
      } else {
        return `Error: I don't see a contact named "${input.assign_contact_name}" in your contacts. Want me to add them first?`;
      }
    }

    const updates: any = {};
    if (assignedContactId) updates.contact_id = assignedContactId;
    if (input.origin) updates.origin = input.origin;
    if (input.destination) updates.destination = input.destination;
    if (input.gross_pay) updates.gross_pay = input.gross_pay;
    if (input.agreed_gross) { updates.agreed_gross = input.agreed_gross; updates.gross_pay = input.agreed_gross; }
    if (input.stage) updates.stage = input.stage;
    if (input.estimated_net) updates.estimated_net = input.estimated_net;
    if (input.estimated_fuel_cost) updates.estimated_fuel_cost = input.estimated_fuel_cost;
    if (input.deadhead_miles !== undefined) updates.deadhead_miles = input.deadhead_miles;
    if (input.loaded_miles !== undefined) updates.loaded_miles = input.loaded_miles;
    if (input.pickup_number) updates.pickup_number = input.pickup_number;
    if (input.broker_number) updates.broker_number = input.broker_number;
    if (input.pro_number) updates.pro_number = input.pro_number;
    if (input.bol_number) updates.bol_number = input.bol_number;
    if (input.notes) {
      const existingNotes = (trip.notes || "").trim();
      const incoming = String(input.notes).trim();
      updates.notes = !existingNotes ? incoming
        : (existingNotes.includes(incoming) ? existingNotes : existingNotes + "\n" + incoming);
    }

    // Recompute net/$hr if gross changed.
    let recomputedNet: number | null = null;
    let recomputedPerHour: number | null = null;
    const newGross = input.agreed_gross ?? input.gross_pay ?? null;
    if (newGross != null && trip.estimate_json) {
      const ej: any = { ...trip.estimate_json };
      const totalCosts = Number(ej.totalCosts) || 0;
      const totalHours = Number(ej.totalHours) || 0;
      const totalMiles = Number(ej.totalMiles) || 0;
      const carrierFrac = (Number(ej.carrierCutPct) || 0) / 100;
      const minGross = Number(ej.minimumGrossNeeded) || 0;
      const g = Number(newGross) || 0;
      const net = g * (1 - carrierFrac) - totalCosts;
      const perHour = totalHours > 0 ? net / totalHours : 0;
      ej.netAtQuote = net; ej.effectiveHourlyRate = perHour;
      ej.carrierCutAmount = g * carrierFrac; ej.quotedGross = g;
      ej.offerPerMile = totalMiles > 0 ? g / totalMiles : 0;
      ej.marginPct = minGross > 0 ? ((g / minGross) - 1) * 100 : 0;
      updates.estimated_net = net; updates.estimate_json = ej;
      recomputedNet = net; recomputedPerHour = perHour;
      if (typeof trip.trip_name === "string" && /- \$\d+$/.test(trip.trip_name)) {
        updates.trip_name = trip.trip_name.replace(/- \$\d+$/, `- $${Math.round(g)}`);
      }
    }

    if (Object.keys(updates).length === 0) {
      return `Found the load (${trip.origin} to ${trip.destination}) but you didn't tell me what to change on it.`;
    }

    const { error: upErr } = await supabase.from("trips").update(updates).eq("id", trip.id);
    if (upErr) return `Error updating load: ${upErr.message || upErr}`;

    const routeNow = `${updates.origin || trip.origin} to ${updates.destination || trip.destination}`;
    const stageNote = input.stage ? ` — marked ${stageLabel(input.stage)}` : "";
    const netNote = recomputedNet != null
      ? `, net ${f(recomputedNet)} (~${f(recomputedPerHour ?? 0)}/hr)`
      : (input.estimated_net ? `, net ${f(input.estimated_net)}` : "");
    return `Updated ${routeNow}${assignNote}${stageNote} — gross ${f(Number(newGross ?? trip.agreed_gross ?? trip.gross_pay))}${netNote}`;
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

// Mileage-weighted regional diesel for the WHOLE route. Pulls per-state miles
// from trucost.app's route decoder (same source as the IFTA burn), prices each
// state's miles at its EIA regional diesel price, and returns the weighted
// average across everything actually driven (deadhead + loaded). This is why a
// California run prices higher than the same miles across TX/Midwest. Falls back
// to the endpoint estimate only if the route breakdown can't be pulled.
async function weightedFuelForRoute(
  pickup: string,
  delivery: string,
  currentLocation: string,
  prices: Record<string, number>,
  nat: number,
): Promise<{ price: number; byState: Record<string, number>; weighted: boolean }> {
  const milesByState: Record<string, number> = {};

  const legs: Array<[string, string]> = [];
  if (currentLocation && pickup) legs.push([currentLocation, pickup]); // deadhead
  if (pickup && delivery) legs.push([pickup, delivery]);               // loaded

  for (const [o, d] of legs) {
    try {
      const sm = await stateMilesForLeg(o, d);
      if (sm) {
        for (const [st, mi] of Object.entries(sm)) {
          milesByState[st] = (milesByState[st] || 0) + (Number(mi) || 0);
        }
      }
    } catch (_) { /* skip this leg, fall through */ }
  }

  const states = Object.keys(milesByState).filter((st) => milesByState[st] >= 1);
  if (states.length === 0) {
    return { price: fuelForRoute(pickup, delivery, prices, nat), byState: {}, weighted: false };
  }

  let weightedSum = 0;
  let totalMiles = 0;
  for (const st of states) {
    const mi = milesByState[st];
    weightedSum += priceForState(st, prices, nat) * mi;
    totalMiles += mi;
  }
  const price = totalMiles > 0 ? weightedSum / totalMiles : nat;
  return { price, byState: milesByState, weighted: true };
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
    totalMiles, totalHours,
    driveHours: emptyDriveHours + loadedDriveHours,
    loadUnloadHours: loadUnload,
    totalFuel, equipment, overhead, totalCosts,
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
      .select("carrier_cut_pct, overhead_pct, hourly_rate, annual_work_hours, speed_empty, speed_loaded, empty_mpg, loaded_mpg, active_truck_id, active_trailer_id, lease_status")
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

    let fuelPrice = 5.35;
    if (input.pickup || input.delivery) {
      const { prices, nat } = await loadRegionalPrices(supabase);
      console.log("fuel regions loaded:", Object.keys(prices).length, Object.keys(prices).join(","));
      const wf = await weightedFuelForRoute(input.pickup || "", input.delivery || "", input.current_location || "", prices, nat);
      fuelPrice = wf.price;
      console.log(`fuel(price_load): weighted=${wf.weighted} price=$${fuelPrice.toFixed(3)} states=${JSON.stringify(Object.fromEntries(Object.entries(wf.byState).map(([k, v]) => [k, Math.round(v)])))}`);
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

async function recommendQuote(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: prof } = await supabase
      .from("profiles")
      .select("carrier_cut_pct, overhead_pct, hourly_rate, annual_work_hours, speed_empty, speed_loaded, empty_mpg, loaded_mpg, active_truck_id, active_trailer_id, lease_status")
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

    const pickup = (input.pickup || "").trim();
    const delivery = (input.delivery || "").trim();

    let fuelPrice = 5.35;
    if (pickup || delivery) {
      const { prices, nat } = await loadRegionalPrices(supabase);
      console.log("fuel regions loaded:", Object.keys(prices).length, Object.keys(prices).join(","));
      const wf = await weightedFuelForRoute(pickup, delivery, input.current_location || "", prices, nat);
      fuelPrice = wf.price;
      console.log(`fuel(recommend_quote): weighted=${wf.weighted} price=$${fuelPrice.toFixed(3)} states=${JSON.stringify(Object.fromEntries(Object.entries(wf.byState).map(([k, v]) => [k, Math.round(v)])))}`);
    }

    const emptyMpg = input.empty_mpg != null
        ? parseFloat(input.empty_mpg)
        : (truck && truck.empty_mpg != null ? parseFloat(truck.empty_mpg) : (parseFloat(pr.empty_mpg) || 6));
    const loadedMpg = input.loaded_mpg != null
        ? parseFloat(input.loaded_mpg)
        : (truck && truck.loaded_mpg != null ? parseFloat(truck.loaded_mpg) : (parseFloat(pr.loaded_mpg) || 5));

    const emptySpeed = input.empty_speed != null ? parseFloat(input.empty_speed) : (parseFloat(pr.speed_empty) || 60);
    const loadedSpeed = input.loaded_speed != null ? parseFloat(input.loaded_speed) : (parseFloat(pr.speed_loaded) || 55);
    const loadUnloadHours = input.load_unload_hours != null ? parseFloat(input.load_unload_hours) : 8;
    const tolls = parseFloat(input.tolls_other) || 0;

    let deadhead = parseFloat(input.deadhead_miles) || 0;
    let loaded = parseFloat(input.loaded_miles) || 0;

    if (loaded < 5 && pickup && delivery) {
      loaded = await getMiles(pickup, delivery);
    }
    if (deadhead < 1 && input.current_location && pickup) {
      deadhead = await getMiles(input.current_location, pickup);
    }

    const truckAnnual = annualCost(truck);
    const trailerAnnual = annualCost(trailer);
    const carrierCutPct = (parseFloat(pr.carrier_cut_pct) || 0) / 100;
    const overheadPct = (parseFloat(pr.overhead_pct) || 0) / 100;
    const annualHours = parseFloat(pr.annual_work_hours) || 2500;
    const target = parseFloat(pr.hourly_rate) || 0;

    // Base compute with zero gross to get fixed costs + exact minGross for target
    const r = computeLoad({
      gross: 0,
      deadhead,
      loaded,
      tolls,
      loadUnloadHours,
      emptyMpg, loadedMpg,
      emptySpeed, loadedSpeed,
      fuelPrice,
      target,
      truckAnnual,
      trailerAnnual,
      carrierCutPct,
      overheadPct,
      annualHours,
    });

    const totalCosts = r.totalCosts;
    const totalHours = r.totalHours;
    const operatorShare = 1 - carrierCutPct;

    const minGrossForTarget = r.minGross || 0;

    // Reasonable profit margin: target + $12/hr
    const desiredPerHour = target + 12;
    const desiredNet = desiredPerHour * totalHours;
    const desiredOperatorGross = desiredNet + totalCosts;
    let recommendedGross = operatorShare > 0 ? (desiredOperatorGross / operatorShare) : desiredOperatorGross;
    recommendedGross = Math.ceil(recommendedGross / 25) * 25; // round nicely

    const f = (n: number) => `$${n.toFixed(0)}`;
    const truckLbl = truck ? `truck ${truck.unit_number || ""}`.trim() : "no active truck";
    const trailerLbl = trailer ? `${trailer.trailer_subtype || "trailer"} ${trailer.unit_number || ""}`.trim() : "no active trailer";

    const distNote = loaded > 0 ? `${loaded} mi loaded${deadhead > 0 ? ` + ${deadhead} deadhead` : ""}` : "miles TBD";

    return `For the ${pickup || "?"} to ${delivery || "?"} run (${distNote}):

Real costs (fuel @ ${f(fuelPrice)}/gal, ${truckLbl} + ${trailerLbl}, overhead, carrier cut) = ~${f(totalCosts)} total.

To just hit your $${f(target)}/hr target you'd need about ${f(minGrossForTarget)} gross.

For a solid buffer (landing you ~$${f(desiredPerHour)}/hr take-home after everything), quote at least ${f(recommendedGross)} on this one.`;
  } catch (e) {
    return `Error figuring recommended quote: ${e}`;
  }
}

// Computes the quote with the real engine (never trusts Charlie's math) and
// writes a COMPLETE row to the quotes table (the Quote Report). Mirrors
// recommendQuote's setup, then saves.
async function saveLoad(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: prof } = await supabase
      .from("profiles")
      .select("carrier_cut_pct, overhead_pct, hourly_rate, annual_work_hours, speed_empty, speed_loaded, empty_mpg, loaded_mpg, active_truck_id, active_trailer_id, lease_status")
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

    const pickup = (input.pickup || "").trim();
    const delivery = (input.delivery || "").trim();

    let fuelPrice = 5.35;
    let fuelByState: Record<string, number> = {};
    if (pickup || delivery) {
      const { prices, nat } = await loadRegionalPrices(supabase);
      console.log("fuel regions loaded:", Object.keys(prices).length, Object.keys(prices).join(","));
      const wf = await weightedFuelForRoute(pickup, delivery, input.current_location || "", prices, nat);
      fuelPrice = wf.price;
      fuelByState = wf.byState;
      console.log(`fuel(save_load): weighted=${wf.weighted} price=$${fuelPrice.toFixed(3)} states=${JSON.stringify(Object.fromEntries(Object.entries(wf.byState).map(([k, v]) => [k, Math.round(v)])))}`);
    }

    const emptyMpg = input.empty_mpg != null ? parseFloat(input.empty_mpg)
        : (truck && truck.empty_mpg != null ? parseFloat(truck.empty_mpg) : (parseFloat(pr.empty_mpg) || 6));
    const loadedMpg = input.loaded_mpg != null ? parseFloat(input.loaded_mpg)
        : (truck && truck.loaded_mpg != null ? parseFloat(truck.loaded_mpg) : (parseFloat(pr.loaded_mpg) || 5));
    const emptySpeed = input.empty_speed != null ? parseFloat(input.empty_speed) : (parseFloat(pr.speed_empty) || 60);
    const loadedSpeed = input.loaded_speed != null ? parseFloat(input.loaded_speed) : (parseFloat(pr.speed_loaded) || 55);
    const loadUnloadHours = input.load_unload_hours != null ? parseFloat(input.load_unload_hours) : 8;
    const tolls = parseFloat(input.tolls_other) || 0;

    let deadhead = parseFloat(input.deadhead_miles) || 0;
    let loaded = parseFloat(input.loaded_miles) || 0;
    if (loaded < 5 && pickup && delivery) loaded = await getMiles(pickup, delivery);
    if (deadhead < 1 && input.current_location && pickup) deadhead = await getMiles(input.current_location, pickup);

    const truckAnnual = annualCost(truck);
    const trailerAnnual = annualCost(trailer);
    const carrierCutPct = (parseFloat(pr.carrier_cut_pct) || 0) / 100;
    const overheadPct = (parseFloat(pr.overhead_pct) || 0) / 100;
    const annualHours = parseFloat(pr.annual_work_hours) || 2500;
    const target = parseFloat(pr.hourly_rate) || 0;
    const operatorShare = 1 - carrierCutPct;

    // Engine pass with gross 0 -> fixed costs + the exact floor to hit target.
    const r = computeLoad({
      gross: 0, deadhead, loaded, tolls, loadUnloadHours,
      emptyMpg, loadedMpg, emptySpeed, loadedSpeed, fuelPrice, target,
      truckAnnual, trailerAnnual, carrierCutPct, overheadPct, annualHours,
    });
    const floorGross = r.minGross || 0;

    // Decide quoted gross: explicit price > margin over floor > default buffer (target + $12/hr).
    let quotedGross: number;
    if (input.quoted_gross != null && parseFloat(input.quoted_gross) > 0) {
      quotedGross = parseFloat(input.quoted_gross);
    } else if (input.margin_pct != null) {
      quotedGross = floorGross * (1 + (parseFloat(input.margin_pct) || 0) / 100);
    } else {
      const desiredNet = (target + 12) * r.totalHours;
      const desiredOperatorGross = desiredNet + r.totalCosts;
      quotedGross = operatorShare > 0 ? desiredOperatorGross / operatorShare : desiredOperatorGross;
      quotedGross = Math.ceil(quotedGross / 25) * 25;
    }
    const marginPct = floorGross > 0 ? ((quotedGross / floorGross) - 1) * 100 : 0;
    const perLoaded = loaded > 0 ? quotedGross / loaded : 0;
    const perTotal = r.totalMiles > 0 ? quotedGross / r.totalMiles : 0;

    // Second pass at the quoted gross -> what the driver actually nets.
    const atQuote = computeLoad({
      gross: quotedGross, deadhead, loaded, tolls, loadUnloadHours,
      emptyMpg, loadedMpg, emptySpeed, loadedSpeed, fuelPrice, target,
      truckAnnual, trailerAnnual, carrierCutPct, overheadPct, annualHours,
    });

    // Resolve contact by name (same as save_trip).
    let contactId = null;
    if (input.contact_name) {
      const { data: contacts } = await supabase
        .from("contacts").select("id, name")
        .eq("user_id", user.id)
        .ilike("name", `%${input.contact_name}%`).limit(1);
      if (contacts && contacts.length > 0) contactId = contacts[0].id;
    }

    const now = new Date();
    const datePfx = `${String(now.getMonth()+1).padStart(2,'0')}${String(now.getDate()).padStart(2,'0')}${now.getFullYear()}`;
    const routeLabel = (pickup && delivery) ? `${pickup} to ${delivery}` : `${Math.round(r.totalMiles)} mi run`;
    const loadName = (input.quote_name && input.quote_name.trim())
        ? input.quote_name.trim()
        : `${datePfx} - ${routeLabel} - $${quotedGross.toFixed(0)}`;

    // stage = sales pipeline: 'quote' (default) -> 'won' / 'lost' -> 'completed'.
    // status stays 'saved' so load_details_screen can still book it (status -> 'booked').
    const stage = (input.stage === "won" || input.stage === "lost" || input.stage === "completed")
      ? input.stage : "quote";
    const offerGross = input.offer_gross != null ? parseFloat(input.offer_gross) : null;
    const costPerMile = r.totalMiles > 0 ? r.totalCosts / r.totalMiles : 0;

    const { error } = await supabase.from("trips").insert({
      user_id: user.id,
      trip_name: loadName,
      origin: pickup || null,
      destination: delivery || null,
      trip_date: now.toISOString().substring(0, 10),
      truck_unit_id: truck ? truck.id : null,
      trailer_unit_id: trailer ? trailer.id : null,
      contact_id: contactId,
      // volunteered operational details (whatever the driver tossed out)
      pickup_number: input.pickup_number || null,
      broker_number: input.broker_number || null,
      bol_number: input.bol_number || null,
      notes: input.notes || null,
      // money lifecycle — gross_pay is the headline the screens read
      gross_pay: quotedGross,
      offer_gross: offerGross,
      quoted_gross: quotedGross,
      agreed_gross: stage === "won" ? quotedGross : null,
      // miles — total_miles is a GENERATED column (deadhead + loaded); do NOT write it
      deadhead_miles: deadhead,
      loaded_miles: loaded,
      // deal-terms snapshot — freeze what was true when this was priced
      carrier_cut_pct_at_time: parseFloat(pr.carrier_cut_pct) || 0,
      lease_status_at_time: pr.lease_status || null,
      // engine results the Saved Trips card reads as columns (no more $0)
      estimated_fuel_cost: r.totalFuel,
      estimated_net: atQuote.net,
      fuel_price_used: fuelPrice,
      // flags
      stage: stage,
      status: "saved",
      estimate_json: {
        // exact keys the Saved Trips card reads:
        effectiveHourlyRate: atQuote.perHour,
        costPerMile: costPerMile,
        offerPerMile: perTotal,
        // full breakdown for completeness:
        totalFuelCost: r.totalFuel,
        equipmentCost: r.equipment,
        overheadCost: r.overhead,
        totalCosts: r.totalCosts,
        totalMiles: r.totalMiles,
        totalHours: r.totalHours,
        driveHours: atQuote.driveHours,
        loadUnloadHours: atQuote.loadUnloadHours,
        carrierCutAmount: atQuote.carrierCut,
        minimumGrossNeeded: floorGross,
        targetHourly: target,
        marginPct: marginPct,
        quotedGross: quotedGross,
        netAtQuote: atQuote.net,
        fuelPriceUsed: fuelPrice,
        fuelByState: fuelByState,
        carrierCutPct: carrierCutPct * 100,
        overheadPct: overheadPct * 100,
        source: "copilot",
      },
    }).select("id").single();

    if (error) return `Error saving load: ${error.message || error}`;

    const f = (n: number) => `$${n.toFixed(0)}`;
    const contactNote = contactId ? ` under ${input.contact_name}`
        : (input.contact_name ? ` (couldn't find ${input.contact_name} in contacts)` : "");
    const stageWord = stage === "won" ? "Saved as a booked load" : "Saved as a quote";
    return `${stageWord}${contactNote}: ${routeLabel}, ${f(quotedGross)} gross (${f(perLoaded)}/loaded mi). Nets about ${f(atQuote.net)}, ~${f(atQuote.perHour)}/hr after everything. Floor to hit your ${f(target)}/hr was ${f(floorGross)}.`;
  } catch (e) {
    return `Error saving load: ${e}`;
  }
}

async function queryAgents(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: agents } = await supabase
      .from("agent_directory")
      .select("id, name, company, phone, email, freight_types, origin_states, trailer_types, min_cargo_insurance, typically_team")
      .eq("is_active", true)
      .order("name", { ascending: true });
    if (!agents || agents.length === 0) return "The agent directory is empty right now.";

    const { data: hidden } = await supabase
      .from("user_agent_status")
      .select("agent_id")
      .eq("user_id", user.id)
      .eq("status", "dismissed");
    const hiddenIds = new Set((hidden || []).map((h: any) => h.agent_id));

    let myInsurance = 100000;
    const { data: prof } = await supabase.from("profiles").select("cargo_insurance").eq("user_id", user.id).maybeSingle();
    if (prof && prof.cargo_insurance != null) myInsurance = Number(prof.cargo_insurance);

    const wantFreight = (input.freight_type || "").toString().toLowerCase().trim();
    const wantTrailer = (input.trailer_type || "").toString().toLowerCase().trim();
    const wantStates = new Set<string>();
    if (input.origin_state) wantStates.add(String(input.origin_state).toUpperCase().trim());
    if (Array.isArray(input.origin_states)) for (const s of input.origin_states) wantStates.add(String(s).toUpperCase().trim());
    const arrHas = (arr: any, want: string) =>
      Array.isArray(arr) && arr.some((x: any) => String(x).toLowerCase().includes(want));
    const stateHit = (a: any) =>
      !wantStates.size || (Array.isArray(a.origin_states) && a.origin_states.some((s: any) => wantStates.has(String(s).toUpperCase())));

    const matches = agents.filter((a: any) => {
      if (hiddenIds.has(a.id)) return false;
      if (wantFreight && !arrHas(a.freight_types, wantFreight)) return false;
      if (wantTrailer && !arrHas(a.trailer_types, wantTrailer)) return false;
      if (!stateHit(a)) return false;
      if (input.team === true && a.typically_team !== true) return false;
      if (input.within_my_insurance === true && a.min_cargo_insurance != null && Number(a.min_cargo_insurance) > myInsurance) return false;
      return true;
    });

    if (matches.length === 0) return "No agents match that. Want me to widen it, or check what's in the directory?";

    const lines = matches.map((a: any) => {
      const co = a.company ? ` @ ${a.company}` : "";
      const ph = a.phone ? ` | ${a.phone}` : "";
      const fr = Array.isArray(a.freight_types) && a.freight_types.length ? ` | ${a.freight_types.join("/")}` : "";
      const st = Array.isArray(a.origin_states) && a.origin_states.length ? ` | out of ${a.origin_states.join(",")}` : "";
      const tm = a.typically_team ? " | TEAM" : "";
      const ins = a.min_cargo_insurance != null ? ` | needs $${Number(a.min_cargo_insurance).toLocaleString()} cargo` : "";
      return `- ${a.name}${co}${ph}${fr}${st}${tm}${ins}`;
    });
    return `Found ${matches.length} agent${matches.length === 1 ? "" : "s"}:\n${lines.join("\n")}`;
  } catch (e) {
    return `Error searching agents: ${e}`;
  }
}

async function whatsNewAgents(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const days = Number(input.days) > 0 ? Number(input.days) : 7;
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();

    const { data: agents } = await supabase
      .from("agent_directory")
      .select("id, name, company, phone, freight_types, typically_team, created_at")
      .eq("is_active", true)
      .gte("created_at", since)
      .order("created_at", { ascending: false });
    if (!agents || agents.length === 0) return `No new agents in the last ${days} days.`;

    const { data: hidden } = await supabase
      .from("user_agent_status")
      .select("agent_id")
      .eq("user_id", user.id)
      .eq("status", "dismissed");
    const hiddenIds = new Set((hidden || []).map((h: any) => h.agent_id));
    const fresh = agents.filter((a: any) => !hiddenIds.has(a.id));
    if (fresh.length === 0) return `No new agents in the last ${days} days.`;

    const lines = fresh.map((a: any) => {
      const co = a.company ? ` @ ${a.company}` : "";
      const ph = a.phone ? ` | ${a.phone}` : "";
      const fr = Array.isArray(a.freight_types) && a.freight_types.length ? ` | ${a.freight_types.join("/")}` : "";
      const tm = a.typically_team ? " | TEAM" : "";
      return `- ${a.name}${co}${ph}${fr}${tm}`;
    });
    return `${fresh.length} new agent${fresh.length === 1 ? "" : "s"} in the last ${days} days:\n${lines.join("\n")}`;
  } catch (e) {
    return `Error checking new agents: ${e}`;
  }
}

async function addAgentToContacts(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";
    const nameQ = (input.agent_name || "").toString().trim();
    if (!nameQ) return "Which agent? Give me a name.";

    const { data: matches } = await supabase
      .from("agent_directory")
      .select("id, name, company, phone, email, origin_states")
      .eq("is_active", true)
      .ilike("name", `%${nameQ}%`)
      .limit(2);
    if (!matches || matches.length === 0) return `Couldn't find an agent named "${nameQ}".`;
    if (matches.length > 1) return `More than one agent matches "${nameQ}": ${matches.map((m: any) => m.name).join(", ")}. Which one?`;
    const a = matches[0];

    const { data: existing } = await supabase
      .from("contacts")
      .select("id")
      .eq("user_id", user.id)
      .eq("source_agent_id", a.id)
      .is("deleted_at", null)
      .limit(1);
    if (existing && existing.length > 0) return `${a.name} is already in your contacts.`;

    const { error: insErr } = await supabase.from("contacts").insert({
      user_id: user.id,
      name: a.name,
      company: a.company,
      phone: a.phone,
      email: a.email,
      contact_type: "Agent",
      best_load_states: Array.isArray(a.origin_states) ? a.origin_states : [],
      source_agent_id: a.id,
    });
    if (insErr) return `Error adding ${a.name}: ${insErr.message}`;

    await supabase.from("user_agent_status").upsert(
      { user_id: user.id, agent_id: a.id, status: "added" },
      { onConflict: "user_id,agent_id" },
    );
    return `Added ${a.name}${a.company ? " (" + a.company + ")" : ""} to your contacts.`;
  } catch (e) {
    return `Error adding agent: ${e}`;
  }
}

async function dismissAgents(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    const { data: agents } = await supabase
      .from("agent_directory")
      .select("id, name, freight_types, origin_states, trailer_types, min_cargo_insurance, typically_team")
      .eq("is_active", true);
    if (!agents || agents.length === 0) return "The agent directory is empty.";

    const { data: hidden } = await supabase
      .from("user_agent_status")
      .select("agent_id")
      .eq("user_id", user.id)
      .eq("status", "dismissed");
    const hiddenIds = new Set((hidden || []).map((h: any) => h.agent_id));

    let myInsurance = 100000;
    const { data: prof } = await supabase.from("profiles").select("cargo_insurance").eq("user_id", user.id).maybeSingle();
    if (prof && prof.cargo_insurance != null) myInsurance = Number(prof.cargo_insurance);

    const wantFreight = (input.freight_type || "").toString().toLowerCase().trim();
    const wantTrailer = (input.trailer_type || "").toString().toLowerCase().trim();
    const wantStates = new Set<string>();
    if (input.origin_state) wantStates.add(String(input.origin_state).toUpperCase().trim());
    if (Array.isArray(input.origin_states)) for (const s of input.origin_states) wantStates.add(String(s).toUpperCase().trim());
    const arrHas = (arr: any, want: string) =>
      Array.isArray(arr) && arr.some((x: any) => String(x).toLowerCase().includes(want));
    const stateHit = (a: any) =>
      !wantStates.size || (Array.isArray(a.origin_states) && a.origin_states.some((s: any) => wantStates.has(String(s).toUpperCase())));
    const matchCriteria = (a: any) => {
      if (wantFreight && !arrHas(a.freight_types, wantFreight)) return false;
      if (wantTrailer && !arrHas(a.trailer_types, wantTrailer)) return false;
      if (!stateHit(a)) return false;
      if (input.team === true && a.typically_team !== true) return false;
      if (input.within_my_insurance === true && a.min_cargo_insurance != null && Number(a.min_cargo_insurance) > myInsurance) return false;
      return true;
    };

    const keepOnly = input.keep_only === true;
    const target = agents.filter((a: any) => {
      if (hiddenIds.has(a.id)) return false; // already hidden
      const m = matchCriteria(a);
      return keepOnly ? !m : m;
    });

    if (target.length === 0) return "Nothing matches that — no agents to hide.";

    const names = target.map((a: any) => a.name).join(", ");
    if (input.confirm !== true) {
      return `PREVIEW — this would hide ${target.length} agent${target.length === 1 ? "" : "s"}: ${names}. Confirm with the driver, then call again with confirm=true.`;
    }

    const rows = target.map((a: any) => ({ user_id: user.id, agent_id: a.id, status: "dismissed" }));
    const { error } = await supabase.from("user_agent_status").upsert(rows, { onConflict: "user_id,agent_id" });
    if (error) return `Error hiding agents: ${error.message}`;
    return `Hid ${target.length} agent${target.length === 1 ? "" : "s"}: ${names}. Say the word and I can bring any back.`;
  } catch (e) {
    return `Error hiding agents: ${e}`;
  }
}

async function restoreAgents(supabase: any, input: any): Promise<string> {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return "Error: not signed in";

    if (input.all === true) {
      const { data: del, error } = await supabase
        .from("user_agent_status")
        .delete()
        .eq("user_id", user.id)
        .eq("status", "dismissed")
        .select("agent_id");
      if (error) return `Error restoring: ${error.message}`;
      const n = (del || []).length;
      return n ? `Brought back ${n} hidden agent${n === 1 ? "" : "s"}.` : "You don't have any hidden agents.";
    }

    const nameQ = (input.agent_name || "").toString().trim();
    if (!nameQ) return "Restore which agent? Give me a name, or say 'all'.";
    const { data: matches } = await supabase
      .from("agent_directory")
      .select("id, name")
      .ilike("name", `%${nameQ}%`)
      .limit(10);
    if (!matches || matches.length === 0) return `Couldn't find an agent named "${nameQ}".`;
    const ids = matches.map((m: any) => m.id);
    const { data: del, error } = await supabase
      .from("user_agent_status")
      .delete()
      .eq("user_id", user.id)
      .eq("status", "dismissed")
      .in("agent_id", ids)
      .select("agent_id");
    if (error) return `Error restoring: ${error.message}`;
    const n = (del || []).length;
    return n ? `Brought back ${n} agent${n === 1 ? "" : "s"} matching "${nameQ}".` : `No hidden agents matched "${nameQ}".`;
  } catch (e) {
    return `Error restoring agents: ${e}`;
  }
}

Deno.serve(async (req) => {
  console.log("copilot build: save_load + floor-in-quote (v4)");
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
      const { message, history, driverName, copilotName, profile: driverProfile, session_id, appGuide } = await req.json();

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
        .select("trip_name, origin, destination, gross_pay, estimated_net, estimated_fuel_cost, total_miles, deadhead_miles, loaded_miles, fuel_price_used, trip_date, estimate_json, pickup_number, broker_number, bol_number, notes, contacts(name, company, phone)")
        .order("trip_date", { ascending: false })
        .limit(20);

      if (trips && trips.length > 0) {
        const tripLines = trips.map((t: any) => {
          const ej = t.estimate_json || {};
          const hourly = (ej.effectiveHourlyRate != null) ? `$${Number(ej.effectiveHourlyRate).toFixed(2)}/hr` : (t.effective_hourly != null ? `$${Number(t.effective_hourly).toFixed(2)}/hr` : "n/a");
          const winner = (t.estimated_net || 0) >= 0 ? "WINNER" : "LOSER";
          const contact = t.contacts ? `Contact: ${t.contacts.name}${t.contacts.company ? ' @ ' + t.contacts.company : ''}${t.contacts.phone ? ' Ph: ' + t.contacts.phone : ''}` : "No contact";
          const refs = [
            t.pickup_number ? `Pickup#: ${t.pickup_number}` : null,
            t.broker_number ? `Broker#: ${t.broker_number}` : null,
            t.bol_number ? `BOL#: ${t.bol_number}` : null,
          ].filter(Boolean).join(" | ");
          const notesNote = t.notes ? ` | Notes: ${String(t.notes).replace(/\n/g, "; ")}` : "";
          return `- ${t.trip_date} | ${t.trip_name || "unnamed"} | ${t.origin || "?"} to ${t.destination || "?"} | ${t.total_miles}mi | Gross: $${t.gross_pay} | Net: $${t.estimated_net != null ? Number(t.estimated_net).toFixed(2) : (t.net_to_operator != null ? Number(t.net_to_operator).toFixed(2) : "0.00")} | ${hourly} | ${winner} | ${contact}${refs ? ' | ' + refs : ''}${notesNote}`;
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

    let contactsContext = "";
    try {
      if (currentUser) {
        const { data: contacts } = await supabase
          .from("contacts")
          .select("name, company, phone, email, city, state, contact_type, star_rating, best_load_states")
          .eq("user_id", currentUser.id)
          .is("deleted_at", null)
          .order("name", { ascending: true });
        if (contacts && contacts.length > 0) {
          const lines = contacts.map((c: any) => {
            const co = c.company ? ` @ ${c.company}` : "";
            const ph = c.phone ? ` | Ph: ${c.phone}` : "";
            const em = c.email ? ` | Email: ${c.email}` : " | Email: none on file";
            const loc = c.city || c.state ? ` | ${[c.city, c.state].filter(Boolean).join(", ")}` : "";
            const type = c.contact_type ? ` | ${c.contact_type}` : "";
            const rating = c.star_rating ? ` | ${c.star_rating}★` : "";
            const states = Array.isArray(c.best_load_states) && c.best_load_states.length
              ? ` | Good loads: ${c.best_load_states.join(", ")}` : "";
            return `- ${c.name}${co}${ph}${em}${loc}${type}${rating}${states}`;
          });
          contactsContext = `\n\nDRIVER'S CONTACTS (brokers, agents, customers):\n${lines.join("\n")}`;
        }
      }
    } catch (e) {
      console.error("Contacts query error:", e);
    }

    let brokerDirectoryContext = "";
    try {
      const { data: brokers } = await supabase
        .from("broker_directory")
        .select("company, dispatch_phone, email, hq_state, coverage, freight_types, notes")
        .eq("is_active", true)
        .order("company", { ascending: true });
      if (brokers && brokers.length > 0) {
        const lines = brokers.map((b: any) => {
          const cov = b.coverage ? ` | ${b.coverage}` : "";
          const ft = b.freight_types ? ` | Freight: ${b.freight_types}` : "";
          const ph = b.dispatch_phone ? ` | Dispatch: ${b.dispatch_phone}` : "";
          const em = b.email ? ` | Email: ${b.email}` : "";
          const hq = b.hq_state ? ` | HQ: ${b.hq_state}` : "";
          const nt = b.notes ? ` | ${b.notes}` : "";
          return `- ${b.company}${cov}${ft}${ph}${em}${hq}${nt}`;
        });
        brokerDirectoryContext = `\n\nBROKER DIRECTORY (shared national call list — every one runs nationwide, so choose by freight type, not state):\n${lines.join("\n")}`;
      }
    } catch (e) {
      console.error("Broker directory query error:", e);
    }

    // Load the driver's profile server-side so rate/overhead/etc. are always current.
    // (The app currently sends no profile, so this used to always fall back to defaults
    //  and the AI was permanently told "Target $50/hr" no matter what the driver set.)
    let dp: any = driverProfile || {};
    if (currentUser) {
      const { data: prof } = await supabase
        .from("profiles")
        .select("carrier_cut_pct, overhead_pct, empty_mpg, loaded_mpg, hourly_rate")
        .eq("user_id", currentUser.id)
        .maybeSingle();
      if (prof) dp = prof;
    }
    const nameContext = `\n\nDRIVER'S NAME: ${driverName || "driver"}\nYOUR NAME: ${copilotName || "Co-Pilot"}. That is your name — answer to it naturally. If the driver calls you by a nickname or a slightly different name, just roll with it; never correct them or insist you are called something else.\n\nDRIVER'S EQUIPMENT: Carrier cut ${dp.carrier_cut_pct ?? 25}%, Overhead ${dp.overhead_pct ?? 15}%, MPG ${dp.empty_mpg ?? 6}empty/${dp.loaded_mpg ?? 5}loaded, Target $${dp.hourly_rate ?? 50}/hr`;

    const appContext = (typeof appGuide === "string" && appGuide.trim())
      ? `\n\n${appGuide.trim()}\n\nWhen the driver asks how to do something in the app, point them to the right screen using this guide.`
      : "";

    const fullSystem = SYSTEM_PROMPT + nameContext + tripContext + fleetContext + contactsContext + brokerDirectoryContext + appContext;

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
        console.log("TOOL CALLED:", tool.name);
        let result = "";
        if (tool.name === "get_driving_distance") {
          result = await getDistance(tool.input.origin, tool.input.destination);
        } else if (tool.name === "recommend_quote") {
          result = await recommendQuote(supabase, tool.input);
        } else if (tool.name === "save_load") {
          result = await saveLoad(supabase, tool.input);
        } else if (tool.name === "get_load") {
          result = await getLoad(supabase, tool.input);
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
        } else if (tool.name === "get_state_fuel_burn") {
          result = await getStateFuelBurn(supabase, tool.input);
        } else if (tool.name === "send_text") {
          actions.push({ type: "sms", phone: tool.input.phone, body: tool.input.message, contact_name: tool.input.contact_name || "" });
          result = `Text message queued for ${tool.input.contact_name || tool.input.phone}.`;
        } else if (tool.name === "make_call") {
          actions.push({ type: "call", phone: tool.input.phone, contact_name: tool.input.contact_name || "" });
          result = `Phone dialer opening for ${tool.input.contact_name || tool.input.phone}.`;
        } else if (tool.name === "send_email") {
          actions.push({ type: "email", email: tool.input.email, subject: tool.input.subject, body: tool.input.body, contact_name: tool.input.contact_name || "" });
          result = `Email drafted to ${tool.input.contact_name || tool.input.email}.`;
        } else if (tool.name === "query_agents") {
          result = await queryAgents(supabase, tool.input);
        } else if (tool.name === "whats_new_agents") {
          result = await whatsNewAgents(supabase, tool.input);
        } else if (tool.name === "add_agent_to_contacts") {
          result = await addAgentToContacts(supabase, tool.input);
        } else if (tool.name === "dismiss_agents") {
          result = await dismissAgents(supabase, tool.input);
        } else if (tool.name === "restore_agents") {
          result = await restoreAgents(supabase, tool.input);
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
