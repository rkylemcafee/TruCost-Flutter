import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// ============================================================
// categorize-receipt
// Receives a receipt photo (base64), sends it to Claude Haiku's
// vision, returns structured JSON keyed to the TruCost categories.
// Detects the real image type from the bytes so it never trusts a
// wrong media_type from the client.
//
// Goes in: supabase/functions/categorize-receipt/index.ts
// Deploy:  supabase functions deploy categorize-receipt
// ============================================================

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_CATEGORIES = [
  "Fuel", "DEF", "Tolls", "Parking", "Scales", "Truck Wash",
  "Maintenance/Repairs", "Tires", "Parts/Supplies", "Permits/Licenses",
  "Insurance", "Meals/Per Diem", "Lodging/Hotel", "Showers", "Laundry",
  "Phone", "Internet", "Office/Software", "Professional Fees",
  "Medical/DOT", "Other",
];

// Read the magic bytes from the start of the image and report the true type,
// so we never tell Anthropic "jpeg" when it's actually a png, etc.
function detectMediaType(b64: string, fallback: string): string {
  try {
    const bin = atob(b64.substring(0, 24)); // 24 b64 chars = 18 bytes
    const b = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
    if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
    if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) return "image/gif";
    if (
      b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50
    ) return "image/webp";
  } catch (_) { /* fall through to fallback */ }
  return fallback || "image/jpeg";
}

function buildSystem(categories: string[]): string {
  return `You read a photo of a receipt for an owner-operator truck driver and extract its details.

Return ONLY a JSON object — no markdown, no code fences, no commentary.

Fields:
- "vendor": business name as printed, or null
- "expense_date": receipt date as YYYY-MM-DD, or null if not visible
- "amount": the TOTAL paid, as a plain number (no $), or null
- "tax_amount": tax charged as a plain number, or null
- "category": choose EXACTLY ONE from this list: ${categories.join(", ")}
- "payment_method": e.g. "Visa", "Cash", "Amex", or null
- "line_items": short array of strings describing what was bought, or []
- "confidence": "high", "medium", or "low"

Rules:
- Choose "category" from what was ACTUALLY purchased, not from the vendor name. A truck stop sells fuel, parking, showers, food, scales, and supplies — never assume fuel. A receipt for a parking spot with no fuel is "Parking".
- If nothing fits, use "Other".
- Use null for anything you cannot read. NEVER guess an amount.
- amount and tax_amount must be plain numbers like 45.20, not strings.`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_base64, media_type, categories } = await req.json();

    if (!image_base64) {
      return new Response(JSON.stringify({ error: "image_base64 required" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const cats = Array.isArray(categories) && categories.length > 0
      ? categories
      : DEFAULT_CATEGORIES;

    // Trust the bytes, not the client's claim.
    const realMediaType = detectMediaType(image_base64, media_type);

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 600,
        system: buildSystem(cats),
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: realMediaType,
                  data: image_base64,
                },
              },
              { type: "text", text: "Extract this receipt as JSON." },
            ],
          },
          { role: "assistant", content: "{" },
        ],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("Anthropic error:", response.status, errText);
      // Pass the real reason back to the app so debugging isn't a log dig.
      return new Response(
        JSON.stringify({ error: "Claude API error", detail: errText, status: response.status }),
        { status: 502, headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    const data = await response.json();
    const textBlocks = (data.content || []).filter((b: any) => b.type === "text");
    const continuation = textBlocks.map((b: any) => b.text).join("").trim();

    let jsonStr = "{" + continuation;
    jsonStr = jsonStr.replace(/```json/gi, "").replace(/```/g, "").trim();
    const firstBrace = jsonStr.indexOf("{");
    const lastBrace = jsonStr.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace !== -1) {
      jsonStr = jsonStr.substring(firstBrace, lastBrace + 1);
    }

    let parsed: any;
    try {
      parsed = JSON.parse(jsonStr);
    } catch (e) {
      console.error("JSON parse failed:", e, "raw:", jsonStr);
      return new Response(
        JSON.stringify({ error: "Could not read receipt", raw: jsonStr }),
        { status: 422, headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    if (!parsed.category || !cats.includes(parsed.category)) {
      parsed.category = "Other";
    }

    return new Response(JSON.stringify(parsed), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    console.error("categorize-receipt error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
