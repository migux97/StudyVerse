import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { componerMensaje, type Envio, escapar, hoyEnArgentina, leerComando, listarPendientes } from "./mensajes.ts";

const base: Envio = {
  id: 1,
  chat_id: -100,
  kind: "actividad",
  grupo: "TP Final",
  tipo: null,
  actor: "Juan",
  payload: {},
  tarea: null,
  responsable: null,
  due_date: null,
};

Deno.test("nueva versión, con nota", () => {
  const m = componerMensaje({
    ...base,
    tipo: "version_subida",
    payload: { nombre: "Informe.docx", version: 3, nota: "corregí la conclusión" },
  });
  assertEquals(
    m,
    "📚 <b>TP Final</b>\n📄 <b>Juan</b> subió la v3 de <b>Informe.docx</b>\n<i>«corregí la conclusión»</i>",
  );
});

Deno.test("primera versión: 'subió el archivo'", () => {
  const m = componerMensaje({ ...base, tipo: "version_subida", payload: { nombre: "a.pdf", version: 1 } });
  assertStringIncludes(m!, "<b>Juan</b> subió <b>a.pdf</b>");
});

Deno.test("bloqueo con hora de Argentina", () => {
  const m = componerMensaje({
    ...base,
    tipo: "archivo_bloqueado",
    payload: { nombre: "Informe.docx", hasta: "2026-11-01T21:30:00Z" },
  });
  assertStringIncludes(m!, "🔒 <b>Juan</b> está editando <b>Informe.docx</b> (hasta las 18:30)");
});

Deno.test("tarea completada", () => {
  const m = componerMensaje({ ...base, tipo: "tarea_completada", payload: { titulo: "Introducción" } });
  assertStringIncludes(m!, "✅ <b>Juan</b> completó <b>Introducción</b>");
});

Deno.test("recordatorio", () => {
  const m = componerMensaje({ ...base, kind: "recordatorio", tarea: "Conclusión", responsable: "Ana" });
  assertEquals(m, "📚 <b>TP Final</b>\n⏰ Mañana vence <b>Conclusión</b> (Ana)");
});

Deno.test("eventos que no se avisan devuelven null", () => {
  assertEquals(componerMensaje({ ...base, tipo: "carpeta_creada" }), null);
});

Deno.test("escapa el HTML que escriben los usuarios", () => {
  assertEquals(escapar("<b>a & b</b>"), "&lt;b&gt;a &amp; b&lt;/b&gt;");
  const m = componerMensaje({ ...base, actor: "<script>", tipo: "tarea_completada", payload: { titulo: "x" } });
  assertStringIncludes(m!, "&lt;script&gt;");
});

Deno.test("leer comandos", () => {
  assertEquals(leerComando("/vincular ABCD-2345"), { tipo: "vincular", codigo: "ABCD-2345" });
  assertEquals(leerComando("/vincular@TPDriveBot abcd2345"), { tipo: "vincular", codigo: "abcd2345" });
  assertEquals(leerComando("/vincular"), { tipo: "vincular", codigo: null });
  assertEquals(leerComando("/start"), { tipo: "ayuda" });
  assertEquals(leerComando("/Pendientes"), { tipo: "pendientes" });
  assertEquals(leerComando("/desvincular"), { tipo: "desvincular" });
  assertEquals(leerComando("hola gente"), { tipo: "ninguno" });
  assertEquals(leerComando(undefined), { tipo: "ninguno" });
});

Deno.test("listar pendientes", () => {
  const texto = listarPendientes([
    { grupo: "TP", titulo: "Intro", responsable: "Juan", due_date: "2026-11-02", estado: "pendiente" },
    { grupo: "TP", titulo: "Gráficos", responsable: null, due_date: "2026-10-30", estado: "en_progreso" },
  ], "2026-11-01");
  assertStringIncludes(texto, "▫️ Intro — Juan · vence mañana");
  assertStringIncludes(texto, "⏳ Gráficos — sin responsable · ⚠️ venció hace 2 días");
  assertEquals(listarPendientes([], "2026-11-01"), "🎉 No hay tareas pendientes.");
});

Deno.test("hoy en Argentina", () => {
  // 01:00 UTC del 2 = 22:00 del 1 en Argentina.
  assertEquals(hoyEnArgentina(new Date("2026-11-02T01:00:00Z")), "2026-11-01");
});
