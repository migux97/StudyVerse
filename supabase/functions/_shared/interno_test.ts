import { assert, assertFalse } from "jsr:@std/assert@1";
import { mismoSecreto } from "./interno.ts";

Deno.test("mismoSecreto: solo acepta el secreto exacto", async () => {
  assert(await mismoSecreto("s3cr3to", "s3cr3to"));
  assertFalse(await mismoSecreto("s3cr3tx", "s3cr3to"));
  assertFalse(await mismoSecreto("s3cr3to-y-mas", "s3cr3to"), "un prefijo correcto no alcanza");
  assertFalse(await mismoSecreto("", "s3cr3to"));
  assertFalse(await mismoSecreto(null, "s3cr3to"));
});

Deno.test("mismoSecreto: sin secreto configurado rechaza todo", async () => {
  assertFalse(await mismoSecreto("cualquiera", undefined));
  assertFalse(await mismoSecreto("", ""));
});
