-- Cuestionarios y evaluaciones virtuales.
--
-- El docente (titular o ayudante) arma un cuestionario para el curso: preguntas
-- de opción única, opción múltiple, respuesta corta (se corrigen solas) y de
-- desarrollo (las corrige a mano). Elige cuándo abre y cierra, si tiene tiempo
-- límite, cuántos intentos hay y cuándo ven el resultado los alumnos.
--
-- Cada alumno rinde por su cuenta (intentos). La app avisa cuando sale de la
-- pantalla (cambia de pestaña o de app, la deja en segundo plano o la cierra y
-- la vuelve a abrir): queda registrado y lo ve el docente. Si el cuestionario
-- tiene tope de salidas, al pasarlo se entrega solo. Abrirlo en otra pestaña u
-- otro dispositivo cuenta como salida y deja sin efecto la pestaña anterior.
--
-- Los alumnos no leen las respuestas correctas ni los puntajes de las tablas:
-- todo pasa por funciones que deciden qué mostrar. La nota se ve al entregar o
-- al cerrar (según el cuestionario); las respuestas correctas, recién cuando
-- cerró o cuando el alumno ya no tiene más intentos.
--
-- El registro de salidas depende de la app: sirve para que el docente vea qué
-- pasó, no es infalible (no detecta otro dispositivo ni a alguien al lado).

-- Tope diario de cuestionarios por curso (como trabajos y fechas).
alter table public.envios_curso drop constraint envios_curso_tipo_check;
alter table public.envios_curso add constraint envios_curso_tipo_check
  check (tipo in ('trabajo', 'material', 'fecha', 'cuestionario'));

create table public.cuestionarios (
  id            uuid primary key default gen_random_uuid(),
  curso_id      uuid not null references public.cursos (id) on delete cascade,
  titulo        text not null check (char_length(trim(titulo)) between 1 and 120),
  descripcion   text check (descripcion is null or char_length(descripcion) <= 4000),
  abre_at       timestamptz not null default now(),
  cierra_at     timestamptz not null,
  -- Tiempo para rendir desde que se empieza (null: hasta que cierra).
  duracion_min  integer check (duracion_min is null or duracion_min between 1 and 600),
  intentos      integer not null default 1 check (intentos between 1 and 20),
  -- Cuándo ve el alumno su nota y las respuestas correctas.
  resultados    text not null default 'al_entregar' check (resultados in ('al_entregar', 'al_cerrar')),
  mezclar       boolean not null default false,
  -- Salidas permitidas: con una más se entrega solo (null: sin tope).
  tope_salidas  integer check (tope_salidas is null or tope_salidas between 0 and 50),
  nota_maxima   numeric(5, 2) not null default 10 check (nota_maxima > 0 and nota_maxima <= 100),
  publicado_at  timestamptz,
  creado_por    uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  check (cierra_at > abre_at)
);

create index cuestionarios_curso_idx on public.cuestionarios (curso_id, cierra_at);

create table public.preguntas (
  id               uuid primary key default gen_random_uuid(),
  cuestionario_id  uuid not null references public.cuestionarios (id) on delete cascade,
  orden            integer not null,
  tipo             text not null check (tipo in ('opcion', 'varias', 'corta', 'desarrollo')),
  enunciado        text not null check (char_length(trim(enunciado)) between 1 and 2000),
  -- Opciones (textos) para 'opcion' y 'varias'.
  opciones         jsonb not null default '[]',
  -- 'opcion' y 'varias': índices de las correctas. 'corta': textos aceptados.
  correctas        jsonb,
  puntos           numeric(5, 2) not null default 1 check (puntos > 0 and puntos <= 100)
);

create index preguntas_cuestionario_idx on public.preguntas (cuestionario_id, orden);

create table public.intentos (
  id               uuid primary key default gen_random_uuid(),
  cuestionario_id  uuid not null references public.cuestionarios (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  group_id         uuid references public.groups (id) on delete set null,
  numero           integer not null check (numero >= 1),
  empezado_at      timestamptz not null default clock_timestamp(),
  vence_at         timestamptz not null,
  entregado_at     timestamptz,
  -- null: lo entregó el alumno; 'tiempo' o 'salidas': se entregó solo.
  entrega_auto     text check (entrega_auto in ('tiempo', 'salidas')),
  puntaje          numeric(7, 2),
  puntaje_max      numeric(7, 2),
  -- Quedan preguntas de desarrollo sin corregir.
  pendiente        boolean not null default false,
  salidas          integer not null default 0 check (salidas >= 0),
  segundos_afuera  integer not null default 0 check (segundos_afuera >= 0),
  afuera_desde     timestamptz,
  -- La pestaña (o el dispositivo) donde se está rindiendo.
  sesion           uuid,
  unique (cuestionario_id, user_id, numero),
  check (entrega_auto is null or entregado_at is not null)
);

create index intentos_grupo_idx on public.intentos (group_id);
create index intentos_abiertos_idx on public.intentos (vence_at) where entregado_at is null;

create table public.respuestas (
  intento_id   uuid not null references public.intentos (id) on delete cascade,
  pregunta_id  uuid not null references public.preguntas (id) on delete cascade,
  valor        jsonb not null,
  -- null: de desarrollo, sin corregir.
  puntaje      numeric(5, 2) check (puntaje is null or puntaje >= 0),
  comentario   text check (comentario is null or char_length(comentario) <= 2000),
  updated_at   timestamptz not null default clock_timestamp(),
  primary key (intento_id, pregunta_id)
);

create index respuestas_pregunta_idx on public.respuestas (pregunta_id);

create table public.intento_eventos (
  id          bigint generated always as identity primary key,
  intento_id  uuid not null references public.intentos (id) on delete cascade,
  tipo        text not null check (tipo in ('empezo', 'salio', 'volvio', 'reabrio', 'entrego')),
  segundos    integer,
  detalle     text,
  at          timestamptz not null default clock_timestamp()
);

create index intento_eventos_idx on public.intento_eventos (intento_id, at);

alter table public.cuestionarios enable row level security;
alter table public.preguntas enable row level security;
alter table public.intentos enable row level security;
alter table public.respuestas enable row level security;
alter table public.intento_eventos enable row level security;

revoke all on public.cuestionarios, public.preguntas, public.intentos, public.respuestas, public.intento_eventos
  from anon, authenticated;
grant select on public.cuestionarios to authenticated;
-- Sin "correctas": esas solo las lee el docente con preguntas_con_clave.
grant select (id, cuestionario_id, orden, tipo, enunciado, opciones, puntos) on public.preguntas to authenticated;

-- ¿Tengo un intento en este cuestionario? (para leer sus preguntas)
create or replace function public.tengo_intento(p_cuestionario_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.intentos i
                 where i.cuestionario_id = p_cuestionario_id and i.user_id = auth.uid())
$$;

revoke execute on function public.tengo_intento(uuid) from public, anon;

create policy "cuestionarios: los docentes y, publicados, los alumnos"
  on public.cuestionarios for select to authenticated
  using (public.soy_docente_del_curso(curso_id)
         or (publicado_at is not null and public.curso_de_mis_grupos(curso_id)));

-- El alumno ve las preguntas recién cuando empieza.
create policy "preguntas: los docentes y quien empezó"
  on public.preguntas for select to authenticated
  using (exists (select 1 from public.cuestionarios c
                 where c.id = preguntas.cuestionario_id and public.soy_docente_del_curso(c.curso_id))
         or public.tengo_intento(cuestionario_id));

-- Corrección automática ------------------------------------------------------------

-- "  Más  Rápido " = "mas rapido"; "2,50" = "2.5".
create or replace function public.normalizar_respuesta(p_texto text)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when x ~ '^-?[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$'
      then trim_scale(replace(replace(x, '.', ''), ',', '.')::numeric)::text
    when x ~ '^-?[0-9]+([.,][0-9]+)?$' then trim_scale(replace(x, ',', '.')::numeric)::text
    else regexp_replace(regexp_replace(translate(lower(x), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '\s+', ' ', 'g'),
                        '[.!?¡¿]+$', '')
  end
  from (select trim(coalesce(p_texto, '')) as x) s
$$;

-- Índices elegidos, sin repetir y ordenados (null si no es una lista de índices válida).
create or replace function public.indices_de(p_valor jsonb, p_cantidad integer)
returns integer[]
language plpgsql immutable set search_path = ''
as $$
declare
  r integer[];
begin
  if jsonb_typeof(p_valor) <> 'array'
     or exists (select 1 from jsonb_array_elements(p_valor) e
                where jsonb_typeof(e) <> 'number' or (e #>> '{}') !~ '^[0-9]{1,3}$'
                   or (e #>> '{}')::integer >= p_cantidad) then
    return null;
  end if;
  select array_agg(distinct (e #>> '{}')::integer order by (e #>> '{}')::integer) into r
  from jsonb_array_elements(p_valor) e;
  if coalesce(cardinality(r), 0) <> jsonb_array_length(p_valor) then
    return null;
  end if;
  return r;
end;
$$;

-- Puntaje de una respuesta (null: de desarrollo, la corrige el docente).
create or replace function public.puntuar(p public.preguntas, p_valor jsonb)
returns numeric
language plpgsql immutable set search_path = ''
as $$
declare
  aceptada text;
begin
  if p_valor is null or p_valor = 'null'::jsonb then
    return 0;
  end if;
  case p.tipo
    when 'opcion', 'varias' then
      return case when public.indices_de(p_valor, jsonb_array_length(p.opciones))
                       = public.indices_de(p.correctas, jsonb_array_length(p.opciones))
                  then p.puntos else 0 end;
    when 'corta' then
      for aceptada in select jsonb_array_elements_text(p.correctas) loop
        if public.normalizar_respuesta(aceptada) = public.normalizar_respuesta(p_valor #>> '{}') then
          return p.puntos;
        end if;
      end loop;
      return 0;
    else
      return null;
  end case;
end;
$$;

-- ¿La respuesta tiene la forma que pide la pregunta?
create or replace function public.valor_valido(p public.preguntas, p_valor jsonb)
returns boolean
language plpgsql immutable set search_path = ''
as $$
declare
  idx integer[];
begin
  case p.tipo
    when 'opcion', 'varias' then
      idx := public.indices_de(p_valor, jsonb_array_length(p.opciones));
      return idx is not null and cardinality(idx) >= 1 and (p.tipo = 'varias' or cardinality(idx) = 1);
    when 'corta' then
      return jsonb_typeof(p_valor) = 'string' and char_length(p_valor #>> '{}') <= 200;
    else
      return jsonb_typeof(p_valor) = 'string' and char_length(p_valor #>> '{}') <= 10000;
  end case;
end;
$$;

revoke execute on function public.indices_de(jsonb, integer) from public, anon, authenticated;
revoke execute on function public.puntuar(public.preguntas, jsonb) from public, anon, authenticated;
revoke execute on function public.valor_valido(public.preguntas, jsonb) from public, anon, authenticated;
revoke execute on function public.normalizar_respuesta(text) from public, anon;

-- Registro de lo que pasa en un intento (hasta 300 eventos por intento).
create or replace function public.evento_intento(p_intento_id uuid, p_tipo text, p_segundos integer default null,
                                                 p_detalle text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if (select count(*) from public.intento_eventos where intento_id = p_intento_id) < 300 then
    insert into public.intento_eventos (intento_id, tipo, segundos, detalle)
    values (p_intento_id, p_tipo, p_segundos, p_detalle);
  end if;
end;
$$;

revoke execute on function public.evento_intento(uuid, text, integer, text) from public, anon, authenticated;

-- Segundos entre dos momentos (0 si se invierten; hasta un día).
create or replace function public.segundos_entre(p_desde timestamptz, p_hasta timestamptz)
returns integer
language sql immutable set search_path = ''
as $$
  select least(greatest(0, floor(extract(epoch from p_hasta - p_desde)))::bigint, 86400)::integer
$$;

-- Suma acotada (un alumno no puede desbordar el contador a fuerza de avisos).
create or replace function public.sumar_afuera(p_total integer, p_seg integer)
returns integer
language sql immutable set search_path = ''
as $$
  select least(p_total::bigint + greatest(coalesce(p_seg, 0), 0), 864000)::integer
$$;

revoke execute on function public.segundos_entre(timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.sumar_afuera(integer, integer) from public, anon, authenticated;

-- Corrige y cierra un intento. [p_motivo]: 'alumno', 'tiempo' o 'salidas'.
create or replace function public.cerrar_intento(p_intento_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  total numeric;
  maximo numeric;
  falta boolean;
  seg integer := 0;
begin
  select * into i from public.intentos where id = p_intento_id for update;
  if i.id is null or i.entregado_at is not null then
    return;
  end if;
  update public.respuestas r set puntaje = public.puntuar(p, r.valor)
  from public.preguntas p
  where p.id = r.pregunta_id and r.intento_id = p_intento_id;

  select coalesce(sum(r.puntaje), 0), coalesce(bool_or(r.puntaje is null), false) into total, falta
  from public.respuestas r where r.intento_id = p_intento_id;
  select coalesce(sum(p.puntos), 0) into maximo from public.preguntas p where p.cuestionario_id = i.cuestionario_id;
  if i.afuera_desde is not null then
    seg := public.segundos_entre(i.afuera_desde, least(clock_timestamp(), i.vence_at));
  end if;

  update public.intentos
  set entregado_at = case when p_motivo = 'tiempo' then least(clock_timestamp(), vence_at) else clock_timestamp() end,
      entrega_auto = nullif(p_motivo, 'alumno'),
      puntaje = total, puntaje_max = maximo, pendiente = falta,
      segundos_afuera = public.sumar_afuera(segundos_afuera, seg), afuera_desde = null
  where id = p_intento_id;
  perform public.evento_intento(p_intento_id, 'entrego', null, p_motivo);
end;
$$;

revoke execute on function public.cerrar_intento(uuid, text) from public, anon, authenticated;

-- Los que se quedaron sin tiempo (cada minuto, y antes de mostrar resultados).
create or replace function public.cerrar_intentos_vencidos(p_cuestionario_id uuid default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  x uuid;
begin
  for x in select i.id from public.intentos i
           where i.entregado_at is null and i.vence_at < clock_timestamp() - interval '15 seconds'
             and (p_cuestionario_id is null or i.cuestionario_id = p_cuestionario_id)
           order by i.id
           for update skip locked
  loop
    begin
      perform public.cerrar_intento(x, 'tiempo');
    exception when others then
      raise warning 'No se pudo cerrar el intento %: %', x, sqlerrm;
    end;
  end loop;
end;
$$;

revoke execute on function public.cerrar_intentos_vencidos(uuid) from public, anon, authenticated;

select cron.schedule('cuestionarios-vencidos', '* * * * *', $$select public.cerrar_intentos_vencidos()$$);

-- ¿El alumno ya puede ver la nota de este intento? (El cierre cuenta pasada la
-- gracia de 15 s, cuando nadie puede cambiar respuestas.)
create or replace function public.resultado_visible(c public.cuestionarios, i public.intentos)
returns boolean
language sql volatile set search_path = ''
as $$
  select i.entregado_at is not null
     and (c.resultados = 'al_entregar' or clock_timestamp() >= c.cierra_at + interval '15 seconds')
$$;

-- ¿Y las respuestas correctas (y el puntaje de cada pregunta)? Solo cuando ya
-- no puede volver a rendir: cerró, o usó todos sus intentos y no tiene uno abierto.
create or replace function public.correctas_visibles(c public.cuestionarios, p_user_id uuid)
returns boolean
language sql volatile set search_path = ''
as $$
  select clock_timestamp() >= c.cierra_at + interval '15 seconds'
      or (c.resultados = 'al_entregar'
          and (select count(*) from public.intentos i where i.cuestionario_id = c.id and i.user_id = p_user_id) >= c.intentos
          and not exists (select 1 from public.intentos i
                          where i.cuestionario_id = c.id and i.user_id = p_user_id and i.entregado_at is null))
$$;

revoke execute on function public.resultado_visible(public.cuestionarios, public.intentos) from public, anon, authenticated;
revoke execute on function public.correctas_visibles(public.cuestionarios, uuid) from public, anon, authenticated;

create or replace function public.intento_json(c public.cuestionarios, i public.intentos, p_con_nota boolean)
returns jsonb
language sql stable set search_path = ''
as $$
  select jsonb_build_object(
    'id', i.id, 'cuestionario_id', i.cuestionario_id, 'user_id', i.user_id, 'numero', i.numero,
    'empezado_at', i.empezado_at, 'vence_at', i.vence_at, 'entregado_at', i.entregado_at,
    'entrega_auto', i.entrega_auto, 'salidas', i.salidas, 'segundos_afuera', i.segundos_afuera,
    'afuera', i.afuera_desde is not null, 'visible', p_con_nota)
  || case when p_con_nota then jsonb_build_object(
       'puntaje', i.puntaje, 'puntaje_max', i.puntaje_max, 'pendiente', i.pendiente,
       'nota', case when i.puntaje_max > 0 then round(i.puntaje / i.puntaje_max * c.nota_maxima, 2) end)
     else '{}'::jsonb end
$$;

revoke execute on function public.intento_json(public.cuestionarios, public.intentos, boolean) from public, anon, authenticated;

-- Docente: armar y publicar ----------------------------------------------------------

create or replace function public.guardar_cuestionario(
  p_id uuid, p_curso_id uuid, p_titulo text, p_descripcion text, p_abre_at timestamptz, p_cierra_at timestamptz,
  p_duracion_min integer, p_intentos integer, p_resultados text, p_mezclar boolean, p_tope_salidas integer,
  p_nota_maxima numeric
)
returns public.cuestionarios
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
  curso uuid := p_curso_id;
begin
  if p_id is not null then
    select * into c from public.cuestionarios where id = p_id for update;
    curso := c.curso_id;
  end if;
  if not public.soy_docente_del_curso(curso) or (p_id is not null and c.id is null) then
    raise exception 'Solo los docentes del curso pueden armar cuestionarios' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_titulo, ''))) not between 1 and 120 then
    raise exception 'Ingresá el nombre (hasta 120 caracteres)' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_descripcion, '')) > 4000 then
    raise exception 'La descripción puede tener hasta 4000 caracteres' using errcode = 'P0001';
  end if;
  if p_cierra_at is null or p_cierra_at <= coalesce(p_abre_at, c.abre_at, now()) then
    raise exception 'El cierre tiene que ser después de la apertura' using errcode = 'P0001';
  end if;
  if p_duracion_min is not null and p_duracion_min not between 1 and 600 then
    raise exception 'El tiempo para rendir va de 1 a 600 minutos' using errcode = 'P0001';
  end if;
  if coalesce(p_intentos, 1) not between 1 and 20 then
    raise exception 'Los intentos van de 1 a 20' using errcode = 'P0001';
  end if;
  if coalesce(p_resultados, 'al_entregar') not in ('al_entregar', 'al_cerrar') then
    raise exception 'Elegí cuándo ven el resultado' using errcode = 'P0001';
  end if;
  if p_tope_salidas is not null and p_tope_salidas not between 0 and 50 then
    raise exception 'Las salidas permitidas van de 0 a 50' using errcode = 'P0001';
  end if;
  if round(coalesce(p_nota_maxima, 10), 2) <= 0 or coalesce(p_nota_maxima, 10) > 100 then
    raise exception 'La nota máxima va de 1 a 100' using errcode = 'P0001';
  end if;

  if p_id is null then
    if not public.hay_lugar(curso, 'cuestionario', 20) then
      raise exception 'Creaste muchos cuestionarios hoy. Probá mañana' using errcode = 'P0001';
    end if;
    insert into public.cuestionarios (curso_id, titulo, descripcion, abre_at, cierra_at, duracion_min, intentos,
                                      resultados, mezclar, tope_salidas, nota_maxima)
    values (curso, trim(p_titulo), nullif(trim(coalesce(p_descripcion, '')), ''), coalesce(p_abre_at, now()),
            p_cierra_at, p_duracion_min, coalesce(p_intentos, 1), coalesce(p_resultados, 'al_entregar'),
            coalesce(p_mezclar, false), p_tope_salidas, coalesce(p_nota_maxima, 10))
    returning * into c;
    return c;
  end if;

  -- Con alumnos que ya empezaron, las reglas para rendir no cambian.
  if exists (select 1 from public.intentos i where i.cuestionario_id = p_id)
     and (p_abre_at is distinct from c.abre_at or p_duracion_min is distinct from c.duracion_min
          or coalesce(p_mezclar, false) <> c.mezclar or p_tope_salidas is distinct from c.tope_salidas
          or coalesce(p_intentos, 1) < c.intentos) then
    raise exception 'Ya hay alumnos que lo empezaron: podés cambiar el nombre, la descripción, el cierre, '
                    'sumar intentos y cuándo ven el resultado' using errcode = 'P0001';
  end if;
  -- Quien ya vio las respuestas correctas no puede volver a rendir.
  if exists (select 1 from public.intentos i where i.cuestionario_id = p_id)
     and clock_timestamp() >= c.cierra_at and p_cierra_at > clock_timestamp() then
    raise exception 'Ya cerró y los alumnos vieron las respuestas: para volver a tomarlo, creá otro cuestionario'
      using errcode = 'P0001';
  end if;
  if coalesce(p_intentos, 1) > c.intentos and c.resultados = 'al_entregar'
     and exists (select 1 from public.intentos i where i.cuestionario_id = p_id
                 group by i.user_id having count(*) >= c.intentos) then
    raise exception 'Hay alumnos que ya usaron todos sus intentos y vieron las respuestas: no se pueden sumar intentos'
      using errcode = 'P0001';
  end if;
  update public.cuestionarios
  set titulo = trim(p_titulo), descripcion = nullif(trim(coalesce(p_descripcion, '')), ''),
      abre_at = coalesce(p_abre_at, abre_at), cierra_at = p_cierra_at, duracion_min = p_duracion_min,
      intentos = coalesce(p_intentos, 1), resultados = coalesce(p_resultados, 'al_entregar'),
      mezclar = coalesce(p_mezclar, false), tope_salidas = p_tope_salidas, nota_maxima = coalesce(p_nota_maxima, 10)
  where id = p_id
  returning * into c;

  -- Los intentos abiertos terminan con el cierre nuevo.
  update public.intentos i
  set vence_at = case when c.duracion_min is null then c.cierra_at
                      else least(i.empezado_at + make_interval(mins => c.duracion_min), c.cierra_at) end
  where i.cuestionario_id = p_id and i.entregado_at is null;
  return c;
end;
$$;

-- Reemplaza todas las preguntas (solo mientras nadie lo empezó).
-- [p_preguntas]: [{tipo, enunciado, opciones, correctas, puntos}, ...]
create or replace function public.guardar_preguntas(p_cuestionario_id uuid, p_preguntas jsonb)
returns setof public.preguntas
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
  q jsonb;
  n integer := 0;
  tipo text;
  opciones jsonb;
  correctas jsonb;
  puntos numeric;
  cant integer;
  idx integer[];
begin
  select * into c from public.cuestionarios where id = p_cuestionario_id for update;
  if c.id is null or not public.soy_docente_del_curso(c.curso_id) then
    raise exception 'Ese cuestionario no existe' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.intentos i where i.cuestionario_id = p_cuestionario_id) then
    raise exception 'Ya hay alumnos que lo empezaron: las preguntas no se pueden cambiar' using errcode = 'P0001';
  end if;
  if p_preguntas is null or jsonb_typeof(p_preguntas) <> 'array' or jsonb_array_length(p_preguntas) > 100 then
    raise exception 'Un cuestionario puede tener hasta 100 preguntas' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_preguntas) = 0 and c.publicado_at is not null then
    raise exception 'Un cuestionario publicado tiene que tener al menos una pregunta' using errcode = 'P0001';
  end if;

  delete from public.preguntas where cuestionario_id = p_cuestionario_id;
  for q in select * from jsonb_array_elements(p_preguntas) loop
    n := n + 1;
    tipo := q->>'tipo';
    opciones := coalesce(q->'opciones', '[]');
    correctas := q->'correctas';
    if coalesce(q->>'puntos', '1') !~ '^[0-9]{1,3}(\.[0-9]+)?$' then
      raise exception 'Pregunta %: los puntos van de 0,01 a 100', n using errcode = 'P0001';
    end if;
    puntos := coalesce((q->>'puntos')::numeric, 1);
    if tipo is null or tipo not in ('opcion', 'varias', 'corta', 'desarrollo') then
      raise exception 'Pregunta %: elegí el tipo', n using errcode = 'P0001';
    end if;
    if char_length(trim(coalesce(q->>'enunciado', ''))) not between 1 and 2000 then
      raise exception 'Pregunta %: escribí la pregunta (hasta 2000 caracteres)', n using errcode = 'P0001';
    end if;
    if round(puntos, 2) <= 0 or puntos > 100 then
      raise exception 'Pregunta %: los puntos van de 0,01 a 100', n using errcode = 'P0001';
    end if;
    if tipo in ('opcion', 'varias') then
      if jsonb_typeof(opciones) <> 'array' or jsonb_array_length(opciones) not between 2 and 10
         or exists (select 1 from jsonb_array_elements(opciones) o
                    where jsonb_typeof(o) <> 'string' or char_length(trim(o #>> '{}')) not between 1 and 300) then
        raise exception 'Pregunta %: poné de 2 a 10 opciones (hasta 300 caracteres cada una)', n using errcode = 'P0001';
      end if;
      cant := jsonb_array_length(opciones);
      idx := public.indices_de(correctas, cant);
      if idx is null or cardinality(idx) = 0 or (tipo = 'opcion' and cardinality(idx) <> 1) then
        raise exception 'Pregunta %: marcá %', n,
          case when tipo = 'opcion' then 'la opción correcta' else 'al menos una opción correcta' end using errcode = 'P0001';
      end if;
      correctas := to_jsonb(idx);
      select jsonb_agg(trim(o)) into opciones from jsonb_array_elements_text(opciones) o;
    elsif tipo = 'corta' then
      if correctas is null or jsonb_typeof(correctas) <> 'array' or jsonb_array_length(correctas) not between 1 and 10
         or exists (select 1 from jsonb_array_elements(correctas) o
                    where jsonb_typeof(o) <> 'string' or char_length(trim(o #>> '{}')) not between 1 and 200) then
        raise exception 'Pregunta %: escribí de 1 a 10 respuestas aceptadas', n using errcode = 'P0001';
      end if;
      select jsonb_agg(trim(o)) into correctas from jsonb_array_elements_text(correctas) o;
      opciones := '[]';
    else
      opciones := '[]';
      correctas := null;
    end if;
    insert into public.preguntas (cuestionario_id, orden, tipo, enunciado, opciones, correctas, puntos)
    values (p_cuestionario_id, n, tipo, trim(q->>'enunciado'), opciones, correctas, puntos);
  end loop;

  return query select * from public.preguntas where cuestionario_id = p_cuestionario_id order by orden;
end;
$$;

-- Las preguntas con las respuestas correctas (para el docente).
create or replace function public.preguntas_con_clave(p_cuestionario_id uuid)
returns setof public.preguntas
language sql stable security definer set search_path = ''
as $$
  select p.* from public.preguntas p
  join public.cuestionarios c on c.id = p.cuestionario_id
  where p.cuestionario_id = p_cuestionario_id and public.soy_docente_del_curso(c.curso_id)
  order by p.orden
$$;

create or replace function public.publicar_cuestionario(p_id uuid)
returns public.cuestionarios
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
  curso text;
begin
  select * into c from public.cuestionarios where id = p_id for update;
  if c.id is null or not public.soy_docente_del_curso(c.curso_id) then
    raise exception 'Ese cuestionario no existe' using errcode = 'P0002';
  end if;
  if c.publicado_at is not null then
    return c;
  end if;
  if not exists (select 1 from public.preguntas p where p.cuestionario_id = p_id) then
    raise exception 'Agregá al menos una pregunta antes de publicarlo' using errcode = 'P0001';
  end if;
  if c.cierra_at <= now() then
    raise exception 'Ya pasó la fecha de cierre: cambiala antes de publicarlo' using errcode = 'P0001';
  end if;
  update public.cuestionarios set publicado_at = now() where id = p_id returning * into c;

  select nombre into curso from public.cursos where id = c.curso_id;
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select gm.user_id, 'curso', left(format('Nuevo cuestionario en %s: %s', curso, c.titulo), 200),
         case when c.abre_at > now()
              then 'Abre el ' || to_char(c.abre_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM "a las" HH24:MI')
              else 'Cierra el ' || to_char(c.cierra_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM "a las" HH24:MI')
         end,
         format('/grupos/%s/cuestionarios/%s', g.id, c.id), g.id
  from (select distinct on (gm.user_id) gm.user_id, g.id
        from public.groups g
        join public.group_members gm on gm.group_id = g.id
        where g.curso_id = c.curso_id and not public.es_docente_del_curso(c.curso_id, gm.user_id)
        order by gm.user_id, g.nombre) as g (user_id, id)
  join public.group_members gm on gm.user_id = g.user_id and gm.group_id = g.id;
  return c;
end;
$$;

create or replace function public.borrar_cuestionario(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.cuestionarios c where c.id = p_id and public.soy_docente_del_curso(c.curso_id)) then
    raise exception 'Ese cuestionario no existe' using errcode = 'P0002';
  end if;
  delete from public.cuestionarios where id = p_id;
end;
$$;

-- Alumno: rendir ---------------------------------------------------------------------

create or replace function public.empezar_intento(p_cuestionario_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
  i public.intentos;
  x uuid;
  grupo uuid;
  usados integer;
begin
  select * into c from public.cuestionarios where id = p_cuestionario_id and publicado_at is not null for share;
  if c.id is null or not public.curso_de_mis_grupos(c.curso_id) then
    raise exception 'Ese cuestionario no existe' using errcode = 'P0002';
  end if;
  if public.soy_docente_del_curso(c.curso_id) then
    raise exception 'Los docentes del curso no rinden sus cuestionarios' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('intento:' || c.id::text || auth.uid()::text));

  for x in select y.id from public.intentos y
           where y.cuestionario_id = c.id and y.user_id = auth.uid() and y.entregado_at is null
             and y.vence_at < clock_timestamp() - interval '15 seconds'
  loop
    perform public.cerrar_intento(x, 'tiempo');
  end loop;
  select * into i from public.intentos y
  where y.cuestionario_id = c.id and y.user_id = auth.uid() and y.entregado_at is null;
  if i.id is not null then
    return i.id;
  end if;

  if clock_timestamp() < c.abre_at then
    raise exception 'Todavía no abrió' using errcode = 'P0001';
  end if;
  if clock_timestamp() >= c.cierra_at then
    raise exception 'Ya cerró' using errcode = 'P0001';
  end if;
  select count(*) into usados from public.intentos y where y.cuestionario_id = c.id and y.user_id = auth.uid();
  if usados >= c.intentos then
    raise exception 'Ya usaste todos tus intentos' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.preguntas p where p.cuestionario_id = c.id) then
    raise exception 'Todavía no tiene preguntas' using errcode = 'P0001';
  end if;

  select g.id into grupo from public.groups g
  join public.group_members gm on gm.group_id = g.id and gm.user_id = auth.uid()
  where g.curso_id = c.curso_id
  order by g.nombre limit 1;

  insert into public.intentos (cuestionario_id, user_id, group_id, numero, vence_at)
  values (c.id, auth.uid(), grupo, usados + 1,
          case when c.duracion_min is null then c.cierra_at
               else least(clock_timestamp() + make_interval(mins => c.duracion_min), c.cierra_at) end)
  returning * into i;
  perform public.evento_intento(i.id, 'empezo');
  return i.id;
end;
$$;

-- Abre el intento en esta pestaña ([p_sesion], un id que inventa la app al
-- abrir la pantalla). Si estaba abierto en otra, cuenta como salida.
create or replace function public.abrir_intento(p_intento_id uuid, p_sesion uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  c public.cuestionarios;
  seg integer;
begin
  if p_sesion is null then
    raise exception 'Falta la sesión' using errcode = 'P0001';
  end if;
  select * into i from public.intentos where id = p_intento_id and user_id = auth.uid() for update;
  if i.id is null then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  select * into c from public.cuestionarios where id = i.cuestionario_id;
  if i.entregado_at is null and clock_timestamp() > i.vence_at + interval '15 seconds' then
    perform public.cerrar_intento(i.id, 'tiempo');
  elsif i.entregado_at is null and i.sesion is distinct from p_sesion then
    if i.sesion is null then
      update public.intentos set sesion = p_sesion where id = i.id;
    else
      -- Volvió a abrirlo (recargó, cerró la app u otra pestaña). Si ya se había
      -- registrado que salió, no se cuenta dos veces.
      seg := case when i.afuera_desde is null then null
                  else public.segundos_entre(i.afuera_desde, clock_timestamp()) end;
      update public.intentos
      set sesion = p_sesion,
          salidas = salidas + case when afuera_desde is null and salidas < 1000 then 1 else 0 end,
          segundos_afuera = public.sumar_afuera(segundos_afuera, seg),
          afuera_desde = null
      where id = i.id
      returning * into i;
      perform public.evento_intento(i.id, 'reabrio', seg);
      if c.tope_salidas is not null and i.salidas > c.tope_salidas then
        perform public.cerrar_intento(i.id, 'salidas');
      end if;
    end if;
  end if;
  select * into i from public.intentos where id = p_intento_id;

  return jsonb_build_object(
    'ahora', clock_timestamp(),
    'cuestionario', to_jsonb(c),
    'intento', public.intento_json(c, i, public.resultado_visible(c, i)),
    'preguntas', case when i.entregado_at is not null then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'orden', p.orden, 'tipo', p.tipo,
                                                   'enunciado', p.enunciado, 'opciones', p.opciones,
                                                   'puntos', p.puntos) order by p.orden), '[]')
      from public.preguntas p where p.cuestionario_id = c.id) end,
    'respuestas', (select coalesce(jsonb_object_agg(r.pregunta_id, r.valor), '{}')
                   from public.respuestas r where r.intento_id = i.id)
  );
end;
$$;

-- Guarda (o borra, con null o vacío) una respuesta mientras el intento sigue abierto.
create or replace function public.responder(p_intento_id uuid, p_sesion uuid, p_pregunta_id uuid, p_valor jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  p public.preguntas;
begin
  select * into i from public.intentos where id = p_intento_id and user_id = auth.uid() for no key update;
  if i.id is null then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  if i.entregado_at is not null or clock_timestamp() > i.vence_at + interval '15 seconds' then
    raise exception 'Se terminó el tiempo: ya no se pueden cambiar las respuestas' using errcode = 'P0001';
  end if;
  -- Código propio: la app lo reconoce para ofrecer "Seguir acá".
  if p_sesion is null or i.sesion is null or i.sesion <> p_sesion then
    raise exception 'Abriste el cuestionario en otra pestaña o dispositivo' using errcode = 'SV001';
  end if;
  select * into p from public.preguntas where id = p_pregunta_id and cuestionario_id = i.cuestionario_id;
  if p.id is null then
    raise exception 'Esa pregunta no es de este cuestionario' using errcode = 'P0001';
  end if;

  if p_valor is null or p_valor = 'null'::jsonb or p_valor = '[]'::jsonb
     or (jsonb_typeof(p_valor) = 'string' and trim(p_valor #>> '{}') = '') then
    delete from public.respuestas where intento_id = i.id and pregunta_id = p.id;
    return;
  end if;
  if not public.valor_valido(p, p_valor) then
    raise exception 'Esa respuesta no sirve para esta pregunta' using errcode = 'P0001';
  end if;
  insert into public.respuestas (intento_id, pregunta_id, valor)
  values (i.id, p.id, p_valor)
  on conflict (intento_id, pregunta_id) do update set valor = excluded.valor, updated_at = clock_timestamp();
end;
$$;

-- La app avisa que el alumno salió ([p_volvio] false) o volvió (true, con los
-- segundos que estuvo afuera según la app, por si el aviso de salida no llegó).
create or replace function public.avisar_salida(p_intento_id uuid, p_sesion uuid, p_volvio boolean, p_segundos integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  c public.cuestionarios;
  seg integer;
begin
  if p_sesion is null then
    raise exception 'Falta la sesión' using errcode = 'P0001';
  end if;
  select * into i from public.intentos where id = p_intento_id and user_id = auth.uid() for update;
  if i.id is null then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  if i.entregado_at is not null or i.sesion is distinct from p_sesion or i.salidas >= 1000
     or clock_timestamp() > i.vence_at + interval '15 seconds' then
    return jsonb_build_object('salidas', i.salidas, 'entregado', i.entregado_at is not null);
  end if;
  select * into c from public.cuestionarios where id = i.cuestionario_id;

  if not coalesce(p_volvio, false) then
    if i.afuera_desde is null then
      update public.intentos set salidas = salidas + 1, afuera_desde = clock_timestamp()
      where id = i.id returning * into i;
      perform public.evento_intento(i.id, 'salio');
    end if;
  else
    if i.afuera_desde is null then
      -- No llegó el aviso de salida: se cuenta acá, con lo que dice la app
      -- (como mucho, lo que lleva rindiendo).
      seg := least(greatest(coalesce(p_segundos, 0), 0), public.segundos_entre(i.empezado_at, clock_timestamp()));
      update public.intentos set salidas = salidas + 1, segundos_afuera = public.sumar_afuera(segundos_afuera, seg)
      where id = i.id returning * into i;
    else
      seg := public.segundos_entre(i.afuera_desde, clock_timestamp());
      update public.intentos set segundos_afuera = public.sumar_afuera(segundos_afuera, seg), afuera_desde = null
      where id = i.id returning * into i;
    end if;
    perform public.evento_intento(i.id, 'volvio', seg);
  end if;

  if c.tope_salidas is not null and i.salidas > c.tope_salidas then
    perform public.cerrar_intento(i.id, 'salidas');
    return jsonb_build_object('salidas', i.salidas, 'entregado', true);
  end if;
  return jsonb_build_object('salidas', i.salidas, 'entregado', false);
end;
$$;

create or replace function public.entregar_intento(p_intento_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
begin
  select * into i from public.intentos where id = p_intento_id and user_id = auth.uid();
  if i.id is null then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  perform public.cerrar_intento(i.id,
    case when clock_timestamp() > i.vence_at + interval '15 seconds' then 'tiempo' else 'alumno' end);
end;
$$;

-- Mis intentos de un cuestionario (con la nota si ya se puede ver).
create or replace function public.mis_intentos(p_cuestionario_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
  x uuid;
begin
  select * into c from public.cuestionarios where id = p_cuestionario_id;
  for x in select y.id from public.intentos y
           where y.cuestionario_id = p_cuestionario_id and y.user_id = auth.uid() and y.entregado_at is null
             and y.vence_at < clock_timestamp() - interval '15 seconds'
  loop
    perform public.cerrar_intento(x, 'tiempo');
  end loop;
  return (select coalesce(jsonb_agg(public.intento_json(c, i, public.resultado_visible(c, i)) order by i.numero), '[]')
          from public.intentos i where i.cuestionario_id = p_cuestionario_id and i.user_id = auth.uid());
end;
$$;

-- Un intento con sus respuestas y su registro de salidas. El docente lo ve
-- todo; el alumno, su nota cuando ya se puede ver y las correctas (con el
-- puntaje de cada pregunta) cuando ya no puede volver a rendir.
create or replace function public.detalle_intento(p_intento_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  c public.cuestionarios;
  docente boolean;
  visible boolean;
  detalle boolean;
begin
  select * into i from public.intentos where id = p_intento_id;
  select * into c from public.cuestionarios where id = i.cuestionario_id;
  docente := c.id is not null and public.soy_docente_del_curso(c.curso_id);
  if i.id is null or not (docente or i.user_id = auth.uid()) then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  if not docente and i.entregado_at is null then
    raise exception 'Todavía no lo entregaste' using errcode = 'P0001';
  end if;
  visible := docente or public.resultado_visible(c, i);
  detalle := docente or (visible and public.correctas_visibles(c, i.user_id));

  return jsonb_build_object(
    'cuestionario', to_jsonb(c),
    'intento', public.intento_json(c, i, visible),
    'detalle_visible', detalle,
    'alumno', (select p.nombre from public.profiles p where p.id = i.user_id),
    'grupo', (select g.nombre from public.groups g where g.id = i.group_id),
    'preguntas', (
      select coalesce(jsonb_agg(
        jsonb_build_object('id', p.id, 'orden', p.orden, 'tipo', p.tipo, 'enunciado', p.enunciado,
                           'opciones', p.opciones, 'puntos', p.puntos, 'valor', r.valor)
        || case when detalle then jsonb_build_object('correctas', p.correctas, 'puntaje', r.puntaje,
                                                     'comentario', r.comentario, 'respondida', r.intento_id is not null)
           else '{}'::jsonb end
        order by p.orden), '[]')
      from public.preguntas p
      left join public.respuestas r on r.pregunta_id = p.id and r.intento_id = i.id
      where p.cuestionario_id = c.id),
    'eventos', (
      select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'segundos', e.segundos, 'detalle', e.detalle,
                                                   'at', e.at) order by e.at, e.id), '[]')
      from public.intento_eventos e where e.intento_id = i.id)
  );
end;
$$;

-- Docente: resultados y corrección ---------------------------------------------------

-- Cada alumno del curso (y quien rindió aunque ya no esté) con sus intentos.
create or replace function public.resultados_del_cuestionario(p_cuestionario_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cuestionarios;
begin
  select * into c from public.cuestionarios where id = p_cuestionario_id;
  if c.id is null or not public.soy_docente_del_curso(c.curso_id) then
    raise exception 'Ese cuestionario no existe' using errcode = 'P0002';
  end if;
  perform public.cerrar_intentos_vencidos(p_cuestionario_id);

  return (
    with alumnos as (
      select gm.user_id, min(g.nombre) as grupo
      from public.groups g join public.group_members gm on gm.group_id = g.id
      where g.curso_id = c.curso_id and not public.es_docente_del_curso(c.curso_id, gm.user_id)
      group by gm.user_id
      union
      select x.user_id, (select g.nombre from public.groups g where g.id = x.group_id)
      from (select i.user_id, min(i.group_id::text)::uuid as group_id
            from public.intentos i
            where i.cuestionario_id = c.id
              and not exists (select 1 from public.groups g join public.group_members gm on gm.group_id = g.id
                              where g.curso_id = c.curso_id and gm.user_id = i.user_id)
            group by i.user_id) x
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'user_id', a.user_id, 'nombre', p.nombre, 'grupo', a.grupo,
             'intentos', (select coalesce(jsonb_agg(public.intento_json(c, i, true) order by i.numero), '[]')
                          from public.intentos i where i.cuestionario_id = c.id and i.user_id = a.user_id))
           order by p.nombre), '[]')
    from alumnos a join public.profiles p on p.id = a.user_id
  );
end;
$$;

-- Puntaje (y comentario) de una respuesta, a mano. Recalcula el total y, si ya
-- no queda nada por corregir, le avisa al alumno.
create or replace function public.corregir_respuesta(p_intento_id uuid, p_pregunta_id uuid, p_puntaje numeric,
                                                     p_comentario text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  i public.intentos;
  c public.cuestionarios;
  p public.preguntas;
  total numeric;
  falta boolean;
begin
  select * into i from public.intentos where id = p_intento_id for update;
  select * into c from public.cuestionarios where id = i.cuestionario_id;
  if i.id is null or not public.soy_docente_del_curso(c.curso_id) then
    raise exception 'Ese intento no existe' using errcode = 'P0002';
  end if;
  if i.entregado_at is null then
    raise exception 'Todavía no lo entregó' using errcode = 'P0001';
  end if;
  select * into p from public.preguntas where id = p_pregunta_id and cuestionario_id = c.id;
  if p.id is null then
    raise exception 'Esa pregunta no es de este cuestionario' using errcode = 'P0001';
  end if;
  if p_puntaje is null or p_puntaje < 0 or p_puntaje > p.puntos then
    raise exception 'El puntaje va de 0 a %', public.nota_texto(p.puntos) using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_comentario, '')) > 2000 then
    raise exception 'El comentario puede tener hasta 2000 caracteres' using errcode = 'P0001';
  end if;

  insert into public.respuestas (intento_id, pregunta_id, valor, puntaje, comentario)
  values (i.id, p.id, 'null'::jsonb, p_puntaje, nullif(trim(coalesce(p_comentario, '')), ''))
  on conflict (intento_id, pregunta_id) do update
    set puntaje = excluded.puntaje, comentario = excluded.comentario;

  select coalesce(sum(r.puntaje), 0), coalesce(bool_or(r.puntaje is null), false) into total, falta
  from public.respuestas r where r.intento_id = i.id;
  update public.intentos set puntaje = total, pendiente = falta where id = i.id returning * into i;

  if not falta and i.group_id is not null and public.resultado_visible(c, i) then
    perform public.notificar(i.user_id, 'nota', format('Corrigieron %s', c.titulo),
      'Nota: ' || public.nota_texto(round(i.puntaje / nullif(i.puntaje_max, 0) * c.nota_maxima, 2)),
      format('/grupos/%s/cuestionarios/%s', i.group_id, c.id), i.group_id);
  end if;
  return public.intento_json(c, i, true);
end;
$$;

revoke execute on function public.guardar_cuestionario(uuid, uuid, text, text, timestamptz, timestamptz, integer, integer,
  text, boolean, integer, numeric) from public, anon;
revoke execute on function public.guardar_preguntas(uuid, jsonb) from public, anon;
revoke execute on function public.preguntas_con_clave(uuid) from public, anon;
revoke execute on function public.publicar_cuestionario(uuid) from public, anon;
revoke execute on function public.borrar_cuestionario(uuid) from public, anon;
revoke execute on function public.empezar_intento(uuid) from public, anon;
revoke execute on function public.abrir_intento(uuid, uuid) from public, anon;
revoke execute on function public.responder(uuid, uuid, uuid, jsonb) from public, anon;
revoke execute on function public.avisar_salida(uuid, uuid, boolean, integer) from public, anon;
revoke execute on function public.entregar_intento(uuid) from public, anon;
revoke execute on function public.mis_intentos(uuid) from public, anon;
revoke execute on function public.detalle_intento(uuid) from public, anon;
revoke execute on function public.resultados_del_cuestionario(uuid) from public, anon;
revoke execute on function public.corregir_respuesta(uuid, uuid, numeric, text) from public, anon;
