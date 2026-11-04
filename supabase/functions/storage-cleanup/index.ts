// Borra de Storage los objetos que ya no usa ninguna versión (grupos
// eliminados, subidas cortadas a la mitad). La llama pg_cron una vez por día.
// Body opcional: { "edad_minima_horas": 24 } — no toca objetos más nuevos,
// para no interferir con una subida en curso.

import { createClient } from "npm:@supabase/supabase-js@2";
import { esLlamadaInterna } from "../_shared/interno.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const LOTE = 100;

Deno.serve(async (req) => {
  if (!(await esLlamadaInterna(req))) return new Response("No autorizado", { status: 401 });

  const body = await req.json().catch(() => ({}));
  const horas = Number.isFinite(body?.edad_minima_horas) ? Math.max(0, body.edad_minima_horas) : 24;

  const { data, error } = await supabase.rpc("orphan_storage_objects", {
    p_edad_minima: `${horas} hours`,
    p_limite: 1000,
  });
  if (error) {
    console.error("orphan_storage_objects", error);
    return Response.json({ error: error.message }, { status: 500 });
  }

  const rutas = (data ?? []) as string[];
  let borrados = 0;
  for (let i = 0; i < rutas.length; i += LOTE) {
    const lote = rutas.slice(i, i + LOTE);
    const { data: ok, error: e } = await supabase.storage.from("archivos").remove(lote);
    if (e) {
      console.error("storage.remove", e);
      continue;
    }
    borrados += ok?.length ?? 0;
  }

  return Response.json({ huerfanos: rutas.length, borrados });
});
