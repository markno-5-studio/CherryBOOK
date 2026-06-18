// ============================================================
// Supabase Edge Function：invoice
// 用途：代理「財政部電子發票 API」查詢發票明細（避開瀏覽器 CORS 限制）
// 部署：Supabase 後台 → Edge Functions → Create function → 名稱填 invoice
//       → 把這整份貼上 → Deploy
// 設定金鑰：Edge Functions → invoice → Secrets（或 Settings → Edge Functions → Secrets）
//       新增 MOF_APP_ID = 你在 einvoice.nat.gov.tw 申請到的 AppID
// ============================================================

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const appID = Deno.env.get("MOF_APP_ID") || "";
    if (!appID) return json({ error: "尚未設定 MOF_APP_ID 金鑰" }, 500);

    const { invNum, invDate, encrypt, sellerID, randomNumber } = await req.json();
    if (!invNum || !invDate) return json({ error: "缺少發票號碼或日期" }, 400);

    const now = new Date();
    const p = (n: number) => String(n).padStart(2, "0");
    const generateTime =
      `${now.getFullYear()}/${p(now.getMonth() + 1)}/${p(now.getDate())} ` +
      `${p(now.getHours())}:${p(now.getMinutes())}:${p(now.getSeconds())}`;

    const params = new URLSearchParams({
      version: "0.5",
      type: "QRCode",
      invNum,
      action: "qryInvDetail",
      generateTime,
      invDate,                       // yyyy/MM/dd
      encrypt: encrypt || "",
      sellerID: sellerID || "",
      UUID: "cherrybook-" + (sellerID || "x"),
      randomNumber: randomNumber || "",
      appID,
    });

    const r = await fetch(
      "https://api.einvoice.nat.gov.tw/PB2CAPIVAN/invapp/InvApp",
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: params.toString(),
      },
    );
    const data = await r.json();
    return json(data, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
