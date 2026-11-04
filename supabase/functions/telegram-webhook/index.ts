// Webhook del bot: Telegram manda acá cada mensaje del chat.
// Responde siempre 200 (si no, Telegram reintenta el mismo mensaje).

import { createClient } from "npm:@supabase/supabase-js@2";
import { AYUDA, escapar, hoyEnArgentina, leerComando, listarPendientes } from "../_shared/mensajes.ts";
import { mismoSecreto } from "../_shared/interno.ts";
import { enviarMensaje } from "../_shared/telegram.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // Telegram manda el secreto que se configuró con setWebhook(secret_token).
  const recibido = req.headers.get("x-telegram-bot-api-secret-token");
  if (!(await mismoSecreto(recibido, Deno.env.get("TELEGRAM_WEBHOOK_SECRET")))) {
    return new Response("No autorizado", { status: 401 });
  }

  const update = await req.json().catch(() => null);
  const mensaje = update?.message;
  if (!mensaje?.chat?.id) return new Response("ok");

  try {
    const respuesta = await responder(mensaje.chat, mensaje.text);
    if (respuesta) await enviarMensaje(mensaje.chat.id, respuesta);
  } catch (e) {
    console.error("telegram-webhook", e);
  }
  return new Response("ok");
});

async function responder(chat: { id: number; title?: string; first_name?: string }, texto?: string) {
  const comando = leerComando(texto);

  switch (comando.tipo) {
    case "ayuda":
      return AYUDA;

    case "vincular": {
      if (!comando.codigo) {
        return "Mandá el código que te dio la app: <code>/vincular ABCD-2345</code>";
      }
      const { data: grupo, error } = await supabase.rpc("redeem_telegram_link_code", {
        p_code: comando.codigo,
        p_chat_id: chat.id,
        p_chat_title: chat.title ?? chat.first_name ?? null,
      });
      if (error) {
        return "❌ Ese código no existe o ya venció. Generá uno nuevo en la app (<i>Conectar Telegram</i>).";
      }
      return `✅ Listo: este chat va a recibir los avisos de <b>${escapar(grupo.nombre)}</b>.\nUsá /pendientes para ver las tareas.`;
    }

    case "desvincular": {
      const { data, error } = await supabase
        .from("telegram_links")
        .delete()
        .eq("chat_id", chat.id)
        .select("groups(nombre)");
      if (error) throw error;
      if (!data?.length) return "Este chat no estaba conectado a ningún grupo.";
      // Sin tipos generados, supabase-js infiere la relación como array; es un objeto.
      const vinculos = data as unknown as { groups: { nombre: string } }[];
      const nombres = vinculos.map((l) => escapar(l.groups.nombre)).join(", ");
      return `👋 Listo, no mando más avisos de ${nombres} a este chat.`;
    }

    case "pendientes": {
      const { data: vinculos, error } = await supabase
        .from("telegram_links")
        .select("group_id")
        .eq("chat_id", chat.id);
      if (error) throw error;
      if (!vinculos?.length) return "Este chat no está conectado a ningún grupo. Usá /vincular CODIGO.";

      const { data: tareas, error: e2 } = await supabase
        .from("tasks")
        .select("titulo, due_date, estado, groups(nombre), assignee:profiles!tasks_assigned_to_fkey(nombre)")
        .in("group_id", vinculos.map((v: { group_id: string }) => v.group_id))
        .neq("estado", "hecha")
        .order("due_date", { ascending: true, nullsFirst: false });
      if (e2) throw e2;

      const filas = (tareas ?? []) as unknown as {
        titulo: string;
        due_date: string | null;
        estado: string;
        groups: { nombre: string };
        assignee: { nombre: string } | null;
      }[];
      return listarPendientes(
        filas.map((t) => ({
          grupo: t.groups.nombre,
          titulo: t.titulo,
          responsable: t.assignee?.nombre ?? null,
          due_date: t.due_date,
          estado: t.estado,
        })),
        hoyEnArgentina(),
      );
    }

    case "ninguno":
      // En los grupos se ignoran los mensajes comunes; en privado, ayuda.
      return chat.id > 0 ? AYUDA : null;
  }
}
