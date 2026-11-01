// Las funciones internas (las llama la base con pg_net / pg_cron) se
// protegen con un secreto compartido: nadie de afuera puede dispararlas.

export function esLlamadaInterna(req: Request): boolean {
  const secreto = Deno.env.get("INTERNAL_FUNCTIONS_SECRET");
  return !!secreto && req.headers.get("x-internal-secret") === secreto;
}
