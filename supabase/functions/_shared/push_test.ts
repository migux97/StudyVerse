import { assert, assertEquals } from "jsr:@std/assert@1";
import { armarMensaje, jwtDeServicio, leerCuenta, type Pendiente, tokenInvalido } from "./push.ts";

const n: Pendiente = {
  id: "n1",
  titulo: "Aviso de Laura Gómez",
  cuerpo: "El parcial pasa al jueves",
  ruta: "/grupos/g1",
  tokens: [],
};

Deno.test("leerCuenta: toma el JSON de Firebase y rechaza lo incompleto", () => {
  assertEquals(leerCuenta(undefined), null);
  assertEquals(leerCuenta("{roto"), null);
  assertEquals(leerCuenta('{"project_id":"p"}'), null);
  const c = leerCuenta('{"project_id":"p","client_email":"a@b.iam.gserviceaccount.com","private_key":"k","extra":1}');
  assertEquals(c?.project_id, "p");
});

Deno.test("armarMensaje: en la web abre la pantalla, en Android va con prioridad alta", () => {
  const web = armarMensaje(n, "tok", "web", "https://studyverse.app/");
  assertEquals(web.message.webpush?.fcm_options.link, "https://studyverse.app/#/grupos/g1");
  assertEquals(web.message.data.ruta, "/grupos/g1");
  assertEquals(web.message.notification.body, "El parcial pasa al jueves");

  const android = armarMensaje({ ...n, cuerpo: null }, "tok", "android", "https://studyverse.app");
  assertEquals(android.message.android?.priority, "high");
  assert(!("body" in android.message.notification));
});

Deno.test("tokenInvalido: se borran los tokens que FCM da por muertos", () => {
  assert(tokenInvalido(404, ""));
  assert(tokenInvalido(400, '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}'));
  assert(!tokenInvalido(500, "UNREGISTERED"));
  assert(!tokenInvalido(429, "quota"));
});

Deno.test("jwtDeServicio: firma RS256 que se puede verificar con la clave pública", async () => {
  const par = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", par.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
  const jwt = await jwtDeServicio({ project_id: "p", client_email: "a@b", private_key: pem }, 1_800_000_000);
  const [cabecera, datos, firma] = jwt.split(".");
  const desde64 = (t: string) => Uint8Array.from(atob(t.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    par.publicKey,
    desde64(firma),
    new TextEncoder().encode(`${cabecera}.${datos}`),
  );
  assert(ok);
  const claims = JSON.parse(new TextDecoder().decode(desde64(datos)));
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(claims.exp - claims.iat, 3600);
});
