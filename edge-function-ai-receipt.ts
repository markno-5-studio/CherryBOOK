// ============================================================
// Supabase Edge Function：ai-receipt
// 用途：用 AI 視覺辨識「收據 / 購買清單」照片，讀出品項與金額
//       （繞過財政部 API 限制——直接「看」收據上的印刷文字）
//
// 部署：Supabase 後台 → Edge Functions → Create function → 名稱填 ai-receipt
//       → 貼上這整份 → Deploy
// 設定金鑰：Edge Functions → Secrets 新增
//       ANTHROPIC_API_KEY = 你在 console.anthropic.com 申請的 API 金鑰
// ============================================================

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 預設用 Opus 4.8（最準）。若想省錢可改成 "claude-haiku-4-5"（較便宜、辨識收據也夠用）。
const MODEL = "claude-opus-4-8";

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const PROMPT =
  "你是收據/發票辨識助手。請看這張圖片，讀出所有購買的品項與各自的金額。" +
  "只回傳純 JSON（不要任何說明文字、不要 markdown 圍欄），格式：" +
  '{"store":"店名或空字串","date":"YYYY-MM-DD 或空字串","items":[{"name":"品名","amount":數字}]}。' +
  "amount 是該品項的小計金額（純數字、台幣、不含貨幣符號）。" +
  "若同一品項有數量，name 可加註數量，amount 為小計。讀不到就回 items 空陣列。";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY") || "";
    if (!apiKey) return json({ error: "尚未設定 ANTHROPIC_API_KEY 金鑰" }, 500);

    const { image, mediaType } = await req.json();
    if (!image) return json({ error: "缺少圖片" }, 400);

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 2000,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mediaType || "image/jpeg", data: image } },
            { type: "text", text: PROMPT },
          ],
        }],
      }),
    });

    const data = await r.json();
    if (data.error) return json({ error: data.error.message || "AI 服務錯誤" }, 500);

    // 取出文字並解析 JSON
    const text = (data.content || []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
    let parsed: any = null;
    try {
      const m = text.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(m ? m[0] : text);
    } catch (_) {
      return json({ error: "AI 回傳格式無法解析", raw: text.slice(0, 300) }, 500);
    }

    // 正規化
    const items = Array.isArray(parsed.items)
      ? parsed.items
          .map((it: any) => ({ name: String(it.name || "").trim(), amount: Number(it.amount) || 0 }))
          .filter((it: any) => it.name)
      : [];
    return json({ store: parsed.store || "", date: parsed.date || "", items });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
