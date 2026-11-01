// Textos del bot (en español) y lectura de comandos. Sin dependencias, para
// poder testearlo con `deno test`.

export const ZONA_HORARIA = "America/Argentina/Buenos_Aires";

/** Una fila de `claim_telegram_outbox`. */
export interface Envio {
  id: number;
  chat_id: number;
  kind: "actividad" | "recordatorio";
  grupo: string;
  tipo: string | null;
  actor: string | null;
  payload: Record<string, unknown> | null;
  tarea: string | null;
  responsable: string | null;
  due_date: string | null;
}

/** Telegram usa parse_mode HTML: hay que escapar lo que escriben los usuarios. */
export function escapar(texto: unknown): string {
  return String(texto ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

const b = (t: unknown) => `<b>${escapar(t)}</b>`;

function hora(iso: unknown): string | null {
  if (typeof iso !== "string") return null;
  const fecha = new Date(iso);
  if (Number.isNaN(fecha.getTime())) return null;
  return new Intl.DateTimeFormat("es-AR", {
    timeZone: ZONA_HORARIA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(fecha);
}

/** Mensaje para un envío de la cola, o null si no hay nada que avisar. */
export function componerMensaje(e: Envio): string | null {
  const encabezado = `📚 ${b(e.grupo)}`;

  if (e.kind === "recordatorio") {
    const quien = e.responsable ? ` (${escapar(e.responsable)})` : " (sin responsable)";
    return `${encabezado}\n⏰ Mañana vence ${b(e.tarea)}${quien}`;
  }

  const p = e.payload ?? {};
  const actor = b(e.actor ?? "Alguien");
  const archivo = b(p.nombre);

  let cuerpo: string | null;
  switch (e.tipo) {
    case "version_subida":
      cuerpo = p.version === 1
        ? `📄 ${actor} subió ${archivo}`
        : `📄 ${actor} subió la v${escapar(p.version)} de ${archivo}`;
      if (typeof p.nota === "string" && p.nota.trim()) {
        cuerpo += `\n<i>«${escapar(p.nota.trim())}»</i>`;
      }
      break;
    case "version_restaurada":
      cuerpo = `↩️ ${actor} restauró la v${escapar(p.desde)} de ${archivo} (ahora es la v${escapar(p.version)})`;
      break;
    case "archivo_bloqueado": {
      const hasta = hora(p.hasta);
      cuerpo = `🔒 ${actor} está editando ${archivo}${hasta ? ` (hasta las ${hasta})` : ""}`;
      break;
    }
    case "archivo_desbloqueado":
      cuerpo = `🔓 ${actor} terminó de editar ${archivo}`;
      break;
    case "desbloqueo_forzado":
      cuerpo = `🔓 ${actor} desbloqueó ${archivo}, que estaba editando ${escapar(p.de ?? "otra persona")}`;
      break;
    case "liberacion_pedida":
      cuerpo = `✋ ${actor} le pidió ${archivo} a ${escapar(p.a ?? "quien lo editaba")}`;
      break;
    case "tarea_completada":
      cuerpo = `✅ ${actor} completó ${b(p.titulo)}`;
      break;
    default:
      cuerpo = null;
  }
  return cuerpo === null ? null : `${encabezado}\n${cuerpo}`;
}

export type Comando =
  | { tipo: "ayuda" }
  | { tipo: "vincular"; codigo: string | null }
  | { tipo: "desvincular" }
  | { tipo: "pendientes" }
  | { tipo: "ninguno" };

/**
 * Lee el comando de un mensaje. En los grupos Telegram agrega el nombre del
 * bot: "/vincular@TPDriveBot ABCD-2345".
 */
export function leerComando(texto: string | undefined): Comando {
  const match = /^\/([a-záéíóú]+)(?:@\w+)?(?:\s+(.+))?$/i.exec((texto ?? "").trim());
  if (!match) return { tipo: "ninguno" };
  const [, nombre, resto] = match;
  switch (nombre.toLowerCase()) {
    case "start":
    case "ayuda":
    case "help":
      return { tipo: "ayuda" };
    case "vincular":
      return { tipo: "vincular", codigo: resto?.trim() || null };
    case "desvincular":
      return { tipo: "desvincular" };
    case "pendientes":
    case "tareas":
      return { tipo: "pendientes" };
    default:
      return { tipo: "ninguno" };
  }
}

export const AYUDA = [
  "👋 Soy el bot de <b>TP Drive</b>. Aviso en este chat cuando alguien de tu grupo:",
  "• sube una versión nueva de un archivo",
  "• empieza o termina de editar uno",
  "• completa una tarea",
  "y recuerdo las fechas límite el día anterior.",
  "",
  "<b>Comandos</b>",
  "/vincular CODIGO — conecta este chat con un grupo de la app (el código lo genera el admin en <i>Conectar Telegram</i>)",
  "/pendientes — tareas sin terminar de los grupos conectados",
  "/desvincular — deja de mandar avisos a este chat",
].join("\n");

export interface TareaPendiente {
  grupo: string;
  titulo: string;
  responsable: string | null;
  due_date: string | null;
  estado: string;
}

/** Respuesta de /pendientes. [hoy] en formato YYYY-MM-DD (hora de Argentina). */
export function listarPendientes(tareas: TareaPendiente[], hoy: string): string {
  if (tareas.length === 0) return "🎉 No hay tareas pendientes.";
  const porGrupo = new Map<string, TareaPendiente[]>();
  for (const t of tareas) porGrupo.set(t.grupo, [...(porGrupo.get(t.grupo) ?? []), t]);

  const lineas: string[] = [];
  for (const [grupo, lista] of porGrupo) {
    lineas.push(`📚 ${b(grupo)}`);
    for (const t of lista) {
      const quien = t.responsable ? escapar(t.responsable) : "sin responsable";
      const cuando = t.due_date ? ` · ${describirFecha(t.due_date, hoy)}` : "";
      const icono = t.estado === "en_progreso" ? "⏳" : "▫️";
      lineas.push(`${icono} ${escapar(t.titulo)} — ${quien}${cuando}`);
    }
    lineas.push("");
  }
  return lineas.join("\n").trim();
}

function describirFecha(fecha: string, hoy: string): string {
  const dias = Math.round((Date.parse(fecha) - Date.parse(hoy)) / 86_400_000);
  if (dias < -1) return `⚠️ venció hace ${-dias} días`;
  if (dias === -1) return "⚠️ venció ayer";
  if (dias === 0) return "vence hoy";
  if (dias === 1) return "vence mañana";
  const [, mes, dia] = fecha.split("-").map(Number);
  return `vence el ${dia}/${mes}`;
}

/** Fecha de hoy en Argentina, YYYY-MM-DD. */
export function hoyEnArgentina(ahora = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: ZONA_HORARIA }).format(ahora);
}
