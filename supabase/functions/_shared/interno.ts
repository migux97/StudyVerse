// Las funciones internas (las llama la base con pg_net / pg_cron) se
// protegen con un secreto compartido: nadie de afuera puede dispararlas.

/**
 * Compara dos secretos en tiempo constante: se comparan sus SHA-256 (mismo
 * largo siempre) recorriendo todos los bytes, así el tiempo de respuesta no
 * revela cuántos caracteres coinciden.
 */
export async function mismoSecreto(recibido: string | null, esperado: string | undefined): Promise<boolean> {
  if (!recibido || !esperado) return false;
  const codificar = (t: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(t));
  const [a, b] = (await Promise.all([codificar(recibido), codificar(esperado)])).map((h) => new Uint8Array(h));
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) diferencia |= a[i] ^ b[i];
  return diferencia === 0;
}

export function esLlamadaInterna(req: Request): Promise<boolean> {
  return mismoSecreto(req.headers.get("x-internal-secret"), Deno.env.get("INTERNAL_FUNCTIONS_SECRET"));
}
