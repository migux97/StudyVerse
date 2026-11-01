// Llamadas a la Bot API de Telegram. El token va en variables de entorno,
// nunca en el código. TELEGRAM_API_BASE permite apuntar a un Telegram
// simulado en las pruebas locales.

const API_BASE = Deno.env.get("TELEGRAM_API_BASE") ?? "https://api.telegram.org";

export class TelegramError extends Error {
  constructor(readonly status: number, readonly descripcion: string) {
    super(`Telegram ${status}: ${descripcion}`);
  }

  /** El chat ya no existe o echaron al bot: no tiene sentido reintentar. */
  get chatPerdido(): boolean {
    return this.status === 403 || (this.status === 400 && /chat not found/i.test(this.descripcion));
  }
}

export async function enviarMensaje(chatId: number, html: string): Promise<void> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!token) throw new Error("Falta TELEGRAM_BOT_TOKEN");

  const res = await fetch(`${API_BASE}/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text: html,
      parse_mode: "HTML",
      disable_web_page_preview: true,
    }),
  });
  if (!res.ok) {
    const cuerpo = await res.json().catch(() => ({}));
    throw new TelegramError(res.status, cuerpo.description ?? res.statusText);
  }
}
