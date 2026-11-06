// Manda por push (Firebase Cloud Messaging) las notificaciones pendientes. La
// llaman la base (pg_net, al crear una notificación) y pg_cron (cada minuto,
// para reintentar). Se protege con el secreto interno.
//
// Configuración (supabase/functions/.env o secretos del proyecto):
//   FCM_SERVICE_ACCOUNT  JSON de la cuenta de servicio de Firebase
//   WEB_URL              dirección de la app web (para abrirla al tocar)
// Sin FCM_SERVICE_ACCOUNT no manda nada: las notificaciones quedan en la app.

import { createClient } from "npm:@supabase/supabase-js@2";
import { esLlamadaInterna } from "../_shared/interno.ts";
import { armarMensaje, jwtDeServicio, leerCuenta, type Pendiente, tokenInvalido } from "../_shared/push.ts";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cuenta = leerCuenta(Deno.env.get("FCM_SERVICE_ACCOUNT"));
// Sin WEB_URL, tocar un push en la web no sabría a dónde ir: no se manda.
const webBase = Deno.env.get("WEB_URL");

let acceso: { token: string; vence: number } | null = null;

async function tokenDeAcceso(): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  if (acceso && acceso.vence > ahora + 60) return acceso.token;
  const jwt = await jwtDeServicio(cuenta!, ahora);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!r.ok) throw new Error(`Google no dio el token de acceso (${r.status})`);
  const j = await r.json();
  acceso = { token: j.access_token, vence: ahora + (j.expires_in ?? 3600) };
  return acceso.token;
}

Deno.serve(async (req) => {
  if (!(await esLlamadaInterna(req))) return new Response("No autorizado", { status: 401 });
  if (!cuenta) return Response.json({ deshabilitado: true });
  if (!webBase) {
    console.error("Falta WEB_URL");
    return Response.json({ error: "Falta WEB_URL" }, { status: 500 });
  }

  let enviadas = 0;
  let fallidas = 0;
  for (let ronda = 0; ronda < 5; ronda++) {
    const { data, error } = await supabase.rpc("tomar_push", { p_limite: 50 });
    if (error) {
      console.error("tomar_push", error);
      return Response.json({ error: error.message }, { status: 500 });
    }
    const pendientes = (data ?? []) as Pendiente[];
    if (pendientes.length === 0) break;

    const bearer = await tokenDeAcceso();
    for (const n of pendientes) {
      let algunaOk = false;
      let todasMuertas = n.tokens.length > 0;
      for (const { token, plataforma } of n.tokens) {
        const r = await fetch(`https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`, {
          method: "POST",
          headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
          body: JSON.stringify(armarMensaje(n, token, plataforma, webBase)),
        });
        if (r.ok) {
          algunaOk = true;
          todasMuertas = false;
          await r.body?.cancel();
          continue;
        }
        const cuerpo = await r.text();
        if (tokenInvalido(r.status, cuerpo)) {
          await supabase.from("dispositivos_push").delete().eq("token", token);
        } else {
          todasMuertas = false;
          console.error("FCM", r.status, cuerpo.slice(0, 300));
        }
      }
      // Si no salió y no fue por tokens muertos, queda pendiente: el cron reintenta.
      const estado = algunaOk ? "enviada" : todasMuertas ? "sin_dispositivos" : null;
      if (estado) {
        await supabase.from("notificaciones").update({ push_estado: estado, push_bloqueo: null }).eq("id", n.id);
      }
      algunaOk ? enviadas++ : fallidas++;
    }
  }
  return Response.json({ enviadas, fallidas });
});
