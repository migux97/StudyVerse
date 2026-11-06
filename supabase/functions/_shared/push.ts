// Push por Firebase Cloud Messaging (API HTTP v1), sin dependencias: la
// cuenta de servicio firma un JWT con WebCrypto y lo cambia por un token de
// acceso de Google.

export type CuentaServicio = { project_id: string; client_email: string; private_key: string };

export type Pendiente = {
  id: string;
  titulo: string;
  cuerpo: string | null;
  ruta: string;
  tokens: { token: string; plataforma: "android" | "web" }[];
};

/** La cuenta de servicio sale de FCM_SERVICE_ACCOUNT (el JSON que baja Firebase). */
export function leerCuenta(json: string | undefined): CuentaServicio | null {
  if (!json) return null;
  try {
    const c = JSON.parse(json);
    if (typeof c.project_id === "string" && typeof c.client_email === "string" && typeof c.private_key === "string") {
      return { project_id: c.project_id, client_email: c.client_email, private_key: c.private_key };
    }
  } catch { /* JSON roto: sin push */ }
  return null;
}

const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const texto64 = (t: string) => base64url(new TextEncoder().encode(t));

function pemABytes(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** JWT firmado (RS256) para pedir un token de acceso con alcance de FCM. */
export async function jwtDeServicio(cuenta: CuentaServicio, ahoraSeg: number): Promise<string> {
  const cabecera = texto64(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const datos = texto64(JSON.stringify({
    iss: cuenta.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahoraSeg,
    exp: ahoraSeg + 3600,
  }));
  const clave = await crypto.subtle.importKey(
    "pkcs8",
    pemABytes(cuenta.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const firma = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", clave, new TextEncoder().encode(`${cabecera}.${datos}`));
  return `${cabecera}.${datos}.${base64url(new Uint8Array(firma))}`;
}

export type MensajeFcm = {
  message: {
    token: string;
    notification: { title: string; body?: string };
    data: Record<string, string>;
    android?: { priority: string; notification: { tag: string } };
    webpush?: { fcm_options: { link: string }; notification: { tag: string; icon: string } };
  };
};

/** Mensaje de FCM v1 para un dispositivo. En la web, tocarlo abre la pantalla. */
export function armarMensaje(n: Pendiente, token: string, plataforma: string, webBase: string): MensajeFcm {
  const enlace = `${webBase.replace(/\/+$/, "")}/#${n.ruta}`;
  return {
    message: {
      token,
      notification: { title: n.titulo, ...(n.cuerpo ? { body: n.cuerpo } : {}) },
      data: { ruta: n.ruta, notificacion: n.id },
      ...(plataforma === "android"
        ? { android: { priority: "high", notification: { tag: n.id } } }
        : { webpush: { fcm_options: { link: enlace }, notification: { tag: n.id, icon: "/icons/Icon-192.png" } } }),
    },
  };
}

/** FCM avisa que el token ya no sirve (desinstalaron la app, se venció…): se borra. */
export function tokenInvalido(status: number, cuerpo: string): boolean {
  if (status === 404) return true;
  return status === 400 && /UNREGISTERED|registration token is not a valid|INVALID_ARGUMENT.*token/i.test(cuerpo);
}
