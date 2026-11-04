// Envía los avisos encolados en `telegram_outbox`. La llaman la base (pg_net,
// al encolar) y pg_cron (cada minuto, para reintentar). Se protege con un
// secreto interno: nadie de afuera puede dispararla.

import { createClient } from "npm:@supabase/supabase-js@2";
import { esLlamadaInterna } from "../_shared/interno.ts";
import { componerMensaje, type Envio } from "../_shared/mensajes.ts";
import { enviarMensaje, TelegramError } from "../_shared/telegram.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MAX_RONDAS = 5;

Deno.serve(async (req) => {
  if (!(await esLlamadaInterna(req))) return new Response("No autorizado", { status: 401 });

  let enviados = 0;
  let fallidos = 0;

  for (let ronda = 0; ronda < MAX_RONDAS; ronda++) {
    const { data, error } = await supabase.rpc("claim_telegram_outbox", { p_limite: 20 });
    if (error) {
      console.error("claim_telegram_outbox", error);
      return Response.json({ error: error.message }, { status: 500 });
    }
    const envios = (data ?? []) as Envio[];
    if (envios.length === 0) break;

    for (const envio of envios) {
      const texto = componerMensaje(envio);
      try {
        if (texto) await enviarMensaje(envio.chat_id, texto);
        await supabase.from("telegram_outbox").update({ sent_at: new Date().toISOString(), last_error: null })
          .eq("id", envio.id);
        enviados++;
      } catch (e) {
        fallidos++;
        const perdido = e instanceof TelegramError && e.chatPerdido;
        await supabase.from("telegram_outbox").update({
          last_error: String(e),
          // Si echaron al bot del chat, no se reintenta…
          ...(perdido ? { attempts: 99 } : {}),
        }).eq("id", envio.id);
        // …y se desvincula ese chat.
        if (perdido) await supabase.from("telegram_links").delete().eq("chat_id", envio.chat_id);
      }
    }
  }

  return Response.json({ enviados, fallidos });
});
