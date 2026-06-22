// ============================================================
// Supabase Edge Function：ai-receipt（Google Gemini 版）
// 用途：用 Gemini AI 視覺辨識「收據 / 購買清單」照片，讀出品項與金額
//
// 部署：Supabase 後台 → Edge Functions → Create function → 名稱填 ai-receipt
//       → 貼上這整份 → Deploy
// 設定金鑰：Edge Functions → Secrets 新增
//       GEMINI_API_KEY = 你在 aistudio.google.com 申請的 Gemini API 金鑰
// ============================================================

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 預設 gemini-2.5-flash（快、便宜、視覺辨識佳）。
// 可改：gemini-2.0-flash（更穩定）/ gemini-2.5-pro（最準、較貴）。
const MODEL = "gemini-2.5-flash";

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const PROMPT =
  "你是收據/發票辨識助手。請看這張圖片，讀出所有購買的品項與各自的金額。" +
  "只回傳純 JSON，格式：" +
  '{"store":"店名或空字串","date":"YYYY-MM-DD 或空字串","items":[{"name":"品名","amount":數字}]}。' +
  "amount 是該品項的小計金額（純數字、台幣、不含貨幣符號）。" +
  "若同一品項有數量，name 可加註數量，amount 為小計。讀不到就回 items 空陣列。";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY") || "";
    if (!apiKey) return json({ error: "尚未設定 GEMINI_API_KEY 金鑰（請到 Edge Functions → Secrets 新增）" }, 200);

    const { image, mediaType } = await req.json();
    if (!image) return json({ error: "缺少圖片" }, 200);

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
    const r = await fetch(url, {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{
          parts: [
            { inline_data: { mime_type: mediaType || "image/jpeg", data: image } },
            { text: PROMPT },
          ],
        }],
        generationConfig: { responseMimeType: "application/json", temperature: 0 },
      }),
    });

    const data = await r.json();
    if (data.error) return json({ error: "Gemini：" + (data.error.message || JSON.stringify(data.error)) }, 200);

    // 取出文字並解析 JSON
    const text = (((data.candidates || [])[0] || {}).content || {}).parts
      ?.map((p: any) => p.text || "").join("") || "";
    let parsed: any = null;
    try {
      const m = text.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(m ? m[0] : text);
    } catch (_) {
      return json({ error: "AI 回傳格式無法解析", raw: String(text).slice(0, 300) }, 200);
    }

    // 正規化
    const items = Array.isArray(parsed.items)
      ? parsed.items
          .map((it: any) => ({ name: String(it.name || "").trim(), amount: Number(it.amount) || 0 }))
          .filter((it: any) => it.name)
      : [];
    return json({ store: parsed.store || "", date: parsed.date || "", items });
  } catch (e) {
    return json({ error: String(e) }, 200);
  }
});
