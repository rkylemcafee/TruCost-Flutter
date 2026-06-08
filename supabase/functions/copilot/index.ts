import "jsr:@supabase/functions-js/edge-runtime.d.ts"

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

const SYSTEM_PROMPT = `You are TruCost Co-Pilot, a voice assistant for owner-operator truck drivers. You help them make smart decisions about which loads to take.

Your personality:
- Talk like a fellow trucker, not a robot. Keep it real.
- Be concise — your responses are spoken aloud while driving. 2-3 sentences max unless they ask for detail.
- Use dollars, miles, and hours — the numbers that matter.
- When they describe a load, help them think through the math: miles, fuel cost, time, and whether the rate makes sense.
- If a load sounds bad, say so directly. If it sounds good, tell them to grab it.

What you know:
- Fuel costs roughly $5-6/gallon diesel depending on region
- Owner-operators need $2.50-3.50/mile ALL-IN to be profitable (varies by equipment costs)
- Deadhead miles are real costs with zero revenue
- A good effective hourly rate for an owner-op is $50-75/hr after ALL costs
- Load/unload time is unpaid time that kills hourly rates on short hauls
- Carrier cut is typically 20-30% for leased operators

Keep responses SHORT for voice. No bullet points, no lists — just talk naturally.`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { message, history } = await req.json();

    if (!message) {
      return new Response(JSON.stringify({ error: "message required" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const messages: Array<{ role: string; content: string }> = [];
    if (Array.isArray(history)) {
      for (const h of history) {
        if (h.role && h.content) messages.push({ role: h.role, content: h.content });
      }
    }
    messages.push({ role: "user", content: message });

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 300,
        system: SYSTEM_PROMPT,
        messages,
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("Anthropic error:", response.status, errText);
      return new Response(JSON.stringify({ error: "Claude API error" }), {
        status: 502,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const data = await response.json();
    const reply = data.content?.[0]?.text ?? "Sorry, I didn't catch that.";

    return new Response(JSON.stringify({ reply }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    console.error("Copilot error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
