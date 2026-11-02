-- Insiel IoT · 02/11/2026 · Catalogo (medidor trifasico, hub IR, controle de AR, lux), zonas e agenda por zona
-- Aplicado no projeto ABRAPE (puepmnyffpfjttxmwfjt), schema iot.

-- ---------- colunas novas ----------
alter table iot.grandezas    add column if not exists bloqueada boolean not null default false;
alter table iot.dispositivos add column if not exists pai_id uuid references iot.dispositivos(id) on delete set null;
alter table iot.dispositivos add column if not exists parametros jsonb not null default '{}'::jsonb;

-- ---------- zonas ----------
create table if not exists iot.zonas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references iot.clientes(id),
  local_id uuid not null references iot.locais(id) on delete cascade,
  nome text not null,
  ordem int not null default 1,
  sensor_dispositivo_id uuid references iot.dispositivos(id) on delete set null,
  sensor_codigo text not null default 'va_temperature',
  modo text not null default 'agenda' check (modo in ('agenda','temperatura')),
  temp_desligar numeric not null default 23,
  temp_religar numeric not null default 25.5,
  leituras_persistencia int not null default 2,
  min_ligado_min int not null default 20,
  min_desligado_min int not null default 15,
  temp_emergencia numeric not null default 27,
  sensor_tolerancia_min int not null default 30,
  criado_em timestamptz not null default now(),
  unique (local_id, nome)
);
create table if not exists iot.zona_dispositivos (
  zona_id uuid not null references iot.zonas(id) on delete cascade,
  dispositivo_id uuid not null references iot.dispositivos(id) on delete cascade,
  primary key (zona_id, dispositivo_id)
);
alter table iot.agendas add column if not exists zona_id uuid references iot.zonas(id) on delete cascade;
alter table iot.agendas add column if not exists escalonar_min int not null default 0;

alter table iot.zonas enable row level security;
alter table iot.zona_dispositivos enable row level security;
grant select, insert, update, delete on iot.zonas, iot.zona_dispositivos to authenticated;
drop policy if exists sel on iot.zonas; drop policy if exists ins on iot.zonas; drop policy if exists upd on iot.zonas; drop policy if exists del on iot.zonas;
create policy sel on iot.zonas for select to authenticated
  using (cliente_id in (select iot.meus_clientes()) and (iot.locais_permitidos(cliente_id) is null or local_id = any (iot.locais_permitidos(cliente_id))));
create policy ins on iot.zonas for insert to authenticated with check (iot.sou_admin(cliente_id));
create policy upd on iot.zonas for update to authenticated using (iot.sou_admin(cliente_id)) with check (iot.sou_admin(cliente_id));
create policy del on iot.zonas for delete to authenticated using (iot.sou_admin(cliente_id));
drop policy if exists sel on iot.zona_dispositivos; drop policy if exists ins on iot.zona_dispositivos; drop policy if exists del on iot.zona_dispositivos;
create policy sel on iot.zona_dispositivos for select to authenticated using (exists (select 1 from iot.zonas z where z.id = zona_id));
create policy ins on iot.zona_dispositivos for insert to authenticated with check (exists (select 1 from iot.zonas z where z.id = zona_id and iot.sou_admin(z.cliente_id)));
create policy del on iot.zona_dispositivos for delete to authenticated using (exists (select 1 from iot.zonas z where z.id = zona_id and iot.sou_admin(z.cliente_id)));

-- ---------- catalogo ----------
insert into iot.tipos_dispositivo (codigo, nome, categoria, alimentacao, descricao, grandezas_padrao) values
('tuya:zndb', 'Medidor de energia trifasico', 'zndb', 'rede',
 'Medidor DIN de ligacao direta. Energia acumulada e tensao/corrente/potencia por fase (decodificadas de phase_a/b/c). O rele interno, se existir, fica BLOQUEADO: nunca comandar.',
 '{"forward_energy_total":{"nome":"Energia acumulada","papel":"leitura","gravar":true},
   "reverse_energy_total":{"nome":"Energia reversa","papel":"leitura","gravar":false},
   "phase_a":{"nome":"Fase A (bruto)","papel":"estado","gravar":false},
   "phase_b":{"nome":"Fase B (bruto)","papel":"estado","gravar":false},
   "phase_c":{"nome":"Fase C (bruto)","papel":"estado","gravar":false},
   "fault":{"nome":"Falha","papel":"estado","gravar":true},
   "balance_energy":{"nome":"Saldo de energia","papel":"estado","gravar":false},
   "switch":{"nome":"Rele interno (bloqueado)","papel":"config","gravar":false,"bloqueada":true},
   "switch_prepayment":{"nome":"Modo pre-pago (bloqueado)","papel":"config","bloqueada":true},
   "clear_energy":{"nome":"Zerar energia (bloqueado)","papel":"config","bloqueada":true},
   "energy_reset":{"nome":"Zerar energia (bloqueado)","papel":"config","bloqueada":true},
   "charge_energy":{"nome":"Recarga pre-paga (bloqueado)","papel":"config","bloqueada":true},
   "tensao_a":{"nome":"Tensao fase A","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"V","escala":1},
   "tensao_b":{"nome":"Tensao fase B","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"V","escala":1},
   "tensao_c":{"nome":"Tensao fase C","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"V","escala":1},
   "corrente_a":{"nome":"Corrente fase A","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"A","escala":2},
   "corrente_b":{"nome":"Corrente fase B","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"A","escala":2},
   "corrente_c":{"nome":"Corrente fase C","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"A","escala":2},
   "potencia_a":{"nome":"Potencia fase A","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"W","escala":0},
   "potencia_b":{"nome":"Potencia fase B","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"W","escala":0},
   "potencia_c":{"nome":"Potencia fase C","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"W","escala":0},
   "potencia_total":{"nome":"Potencia total","papel":"leitura","gravar":true,"derivada":true,"tipo":"Integer","unidade":"W","escala":0}}'),
('tuya:wnykq', 'Hub infravermelho (emissor IR)', 'wnykq', 'rede',
 'Emissor IR Wi-Fi. Cada controle virtual criado no app vira um dispositivo filho (tuya:infrared_ac). Se o hub tiver sensor, informa temperatura e umidade.',
 '{"va_temperature":{"nome":"Temperatura","papel":"leitura","gravar":true},"va_humidity":{"nome":"Umidade","papel":"leitura","gravar":true}}'),
('tuya:infrared_ac', 'Controle de ar-condicionado (IR)', 'infrared_ac', 'rede',
 'Controle virtual de um hub IR. power 0/1 · mode 0 frio, 1 calor, 2 auto, 3 ventilar, 4 desumidificar · temp 16-30 · wind 0 auto, 1 baixa, 2 media, 3 alta. Estado presumido: o IR nao tem retorno do aparelho. Parametros do dispositivo (mode, wind, temp) sao usados ao ligar.',
 '{"power":{"nome":"Ligado","papel":"leitura","gravar":true,"tipo":"Integer","faixa":{"min":0,"max":1,"step":1}},
   "mode":{"nome":"Modo","papel":"config","gravar":false,"tipo":"Integer","faixa":{"min":0,"max":4,"step":1}},
   "temp":{"nome":"Temperatura ajustada","papel":"leitura","gravar":true,"tipo":"Integer","unidade":"℃","faixa":{"min":16,"max":30,"step":1}},
   "wind":{"nome":"Ventilacao","papel":"config","gravar":false,"tipo":"Integer","faixa":{"min":0,"max":3,"step":1}}}'),
('tuya:ldcg', 'Sensor de luminosidade', 'ldcg', 'rede',
 'Mede a iluminancia (lux). Usado para reduzir a iluminacao com luz natural suficiente.',
 '{"bright_value":{"nome":"Luminosidade","papel":"leitura","gravar":true},"battery_percentage":{"nome":"Bateria","papel":"leitura","gravar":true}}')
on conflict (codigo) do update
  set nome = excluded.nome, categoria = excluded.categoria, alimentacao = excluded.alimentacao,
      descricao = excluded.descricao, grandezas_padrao = excluded.grandezas_padrao;

update iot.tipos_dispositivo
   set grandezas_padrao = grandezas_padrao || '{"switch_usb1":{"nome":"Saida USB","papel":"leitura","gravar":true},"switch_2":{"nome":"Saida 2","papel":"leitura","gravar":true}}'::jsonb,
       descricao = 'Liga/desliga e mede corrente, potencia, tensao e energia acumulada. Modelos com USB tem saida USB separada (switch_usb1).'
 where codigo = 'tuya:cz';
update iot.tipos_dispositivo
   set descricao = 'Liga/desliga o circuito e, nos modelos com medicao, informa corrente, potencia, tensao e energia. Conferir relay_status = ligado ao religar quando alimenta iluminacao.'
 where codigo = 'tuya:dlq';

-- ---------- grandezas a partir do padrao do tipo (derivadas e controles IR) ----------
create or replace function iot.grandezas_de_padrao(p_disp uuid, p_padrao jsonb, p_somente_derivadas boolean, p_comandavel boolean)
returns int language plpgsql security definer set search_path to 'iot', 'public' as $$
declare k text; v jsonb; n int := 0;
begin
  for k, v in select * from jsonb_each(coalesce(p_padrao, '{}'::jsonb)) loop
    if p_somente_derivadas and coalesce((v->>'derivada')::boolean, false) is not true then continue; end if;
    insert into iot.grandezas (dispositivo_id, codigo, nome, tipo_valor, unidade, escala, faixa, papel, gravar, comandavel, bloqueada)
    values (p_disp, k, coalesce(v->>'nome', k), coalesce(v->>'tipo', 'Integer'), v->>'unidade', coalesce((v->>'escala')::int, 0),
            coalesce(v->'faixa', '{}'::jsonb), coalesce(v->>'papel', 'leitura'), coalesce((v->>'gravar')::boolean, false),
            p_comandavel and coalesce((v->>'derivada')::boolean, false) is not true, coalesce((v->>'bloqueada')::boolean, false))
    on conflict (dispositivo_id, codigo) do update
      set tipo_valor = excluded.tipo_valor, unidade = coalesce(excluded.unidade, iot.grandezas.unidade),
          escala = excluded.escala, faixa = excluded.faixa, comandavel = excluded.comandavel, bloqueada = excluded.bloqueada;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- leituras derivadas (medidor trifasico: fases em base64) ----------
create or replace function iot.derivadas(p_categoria text, p_estado jsonb)
returns jsonb language plpgsql immutable as $$
declare v jsonb := '{}'::jsonb; f text; b bytea; vt numeric; ia numeric; pw numeric; ptot numeric := 0; n int := 0;
begin
  if p_categoria = 'zndb' then
    foreach f in array array['a','b','c'] loop
      if jsonb_typeof(p_estado -> ('phase_' || f)) = 'string' and length(p_estado ->> ('phase_' || f)) > 0 then
        begin
          b := decode(p_estado ->> ('phase_' || f), 'base64');
          if length(b) >= 8 then
            vt := (get_byte(b, 0) * 256 + get_byte(b, 1)) / 10.0;                           -- V, 0,1 V
            ia := (get_byte(b, 2) * 65536 + get_byte(b, 3) * 256 + get_byte(b, 4)) / 1000.0;  -- A, 1 mA
            pw := get_byte(b, 5) * 65536 + get_byte(b, 6) * 256 + get_byte(b, 7);             -- W
            v := v || jsonb_build_object('tensao_' || f, vt, 'corrente_' || f, ia, 'potencia_' || f, pw);
            ptot := ptot + pw; n := n + 1;
          end if;
        exception when others then null; end;
      end if;
    end loop;
    if n > 0 then v := v || jsonb_build_object('potencia_total', ptot); end if;
  end if;
  return v;
end $$;

-- ---------- comandar: respeita bloqueio ----------
create or replace function iot.comandar(p_dispositivo_id uuid, p_codigo text, p_valor jsonb, p_por text default 'dashboard', p_regra_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'iot', 'public' as $$
declare v_id bigint;
begin
  if exists (select 1 from iot.grandezas where dispositivo_id = p_dispositivo_id and codigo = p_codigo and bloqueada) then
    raise exception 'comando % bloqueado neste dispositivo', p_codigo;
  end if;
  insert into iot.comandos (dispositivo_id, codigo, valor, solicitado_por, regra_id)
  values (p_dispositivo_id, p_codigo, p_valor, p_por, p_regra_id) returning id into v_id;
  return iot.enviar_comando(v_id);
end $$;

-- ---------- enviar_comando: dispositivos Tuya comuns e controles IR ----------
create or replace function iot.enviar_comando(p_comando_id bigint)
returns jsonb language plpgsql security definer set search_path to 'iot', 'extensions', 'public' as $$
declare c iot.comandos; d iot.dispositivos; h iot.dispositivos; f iot.fontes; r jsonb; v_body jsonb; v_num numeric;
begin
  select * into c from iot.comandos where id = p_comando_id;
  select * into d from iot.dispositivos where id = c.dispositivo_id;
  begin
    f := iot.tuya_token(d.fonte_id);
    if d.pai_id is not null and d.categoria like 'infrared%' then
      select * into h from iot.dispositivos where id = d.pai_id;
      v_num := nullif(regexp_replace(c.valor #>> '{}', '[^0-9.-]', '', 'g'), '')::numeric;
      if c.codigo = 'power' and v_num = 1 then
        -- ao ligar, manda a cena completa: modo/ventilacao/temperatura dos parametros do dispositivo (ou do ultimo estado)
        v_body := jsonb_build_object(
          'power', 1,
          'mode', coalesce((d.parametros->>'mode')::int, nullif(regexp_replace(d.estado_atual->>'mode', '[^0-9]', '', 'g'), '')::int, 0),
          'temp', coalesce((d.parametros->>'temp')::int, nullif(regexp_replace(d.estado_atual->>'temp', '[^0-9]', '', 'g'), '')::int, 24),
          'wind', coalesce((d.parametros->>'wind')::int, nullif(regexp_replace(d.estado_atual->>'wind', '[^0-9]', '', 'g'), '')::int, 0));
        r := iot.tuya_request(f, 'POST', '/v1.0/infrareds/' || h.id_externo || '/air-conditioners/' || d.id_externo || '/scenes/command', '', v_body::text);
        update iot.dispositivos set estado_atual = estado_atual || v_body, ultima_mudanca_em = now(), atualizado_em = now() where id = d.id;
      else
        r := iot.tuya_request(f, 'POST', '/v2.0/infrareds/' || h.id_externo || '/air-conditioners/' || d.id_externo || '/command', '',
               jsonb_build_object('code', c.codigo, 'value', coalesce(to_jsonb(v_num), c.valor))::text);
        update iot.dispositivos set estado_atual = estado_atual || jsonb_build_object(c.codigo, coalesce(to_jsonb(v_num), c.valor)),
               ultima_mudanca_em = now(), atualizado_em = now() where id = d.id;
      end if;
    else
      r := iot.tuya_request(f, 'POST', '/v1.0/iot-03/devices/' || d.id_externo || '/commands', '',
             jsonb_build_object('commands', jsonb_build_array(jsonb_build_object('code', c.codigo, 'value', c.valor)))::text);
    end if;
    update iot.comandos set status = 'enviado', resposta = coalesce(r, 'true'::jsonb), enviado_em = now() where id = p_comando_id;
    return coalesce(r, 'true'::jsonb);
  exception when others then
    update iot.comandos set status = 'erro', resposta = jsonb_build_object('erro', sqlerrm), enviado_em = now() where id = p_comando_id;
    insert into iot.eventos (cliente_id, dispositivo_id, regra_id, tipo, severidade, titulo, detalhe)
    values (d.cliente_id, d.id, c.regra_id, 'comando', 'critico', 'Falha ao comandar ' || d.nome,
            jsonb_build_object('codigo', c.codigo, 'valor', c.valor, 'erro', sqlerrm));
    return jsonb_build_object('erro', sqlerrm);
  end;
end $$;

-- ---------- sincronizacao: padrao com bloqueio, derivadas e controles IR do hub ----------
create or replace function iot.tuya_sincronizar(p_fonte_id uuid)
returns integer language plpgsql security definer set search_path to 'iot', 'extensions', 'public' as $$
declare
  f iot.fontes; r jsonb; d jsonb; s jsonb; spec jsonb; v_vals jsonb; v_p jsonb; v_pad jsonb;
  v_lrk text := ''; v_tipo uuid; v_alim text; v_did uuid; n int := 0;
  v_fn_codes text[]; v_papel text; v_gravar boolean; v_cat text;
  hub record; rem jsonb; v_rem_tipo uuid; v_rem_pad jsonb; v_rem_cat text;
begin
  f := iot.tuya_token(p_fonte_id);
  loop
    r := iot.tuya_request(f, 'GET', '/v1.0/iot-01/associated-users/devices', 'last_row_key=' || v_lrk || '&size=100');
    for d in select * from jsonb_array_elements(coalesce(r->'devices', '[]'::jsonb)) loop
      v_cat := d->>'category';
      select id, alimentacao, grandezas_padrao into v_tipo, v_alim, v_pad
        from iot.tipos_dispositivo where codigo = 'tuya:' || v_cat;
      v_pad := coalesce(v_pad, '{}'::jsonb);
      insert into iot.dispositivos (cliente_id, fonte_id, tipo_id, id_externo, nome, produto, categoria, alimentacao, online)
      values (f.cliente_id, f.id, v_tipo, d->>'id', coalesce(d->>'name', d->>'id'), d->>'product_name',
              v_cat, coalesce(v_alim, 'bateria'), (d->>'online')::boolean)
      on conflict (fonte_id, id_externo) do update
        set produto = excluded.produto, categoria = excluded.categoria,
            tipo_id = coalesce(iot.dispositivos.tipo_id, excluded.tipo_id), atualizado_em = now()
      returning id into v_did;

      begin
        spec := iot.tuya_request(f, 'GET', '/v1.0/iot-03/devices/' || (d->>'id') || '/specification');
      exception when others then
        spec := '{}'::jsonb;   -- controles IR e alguns filhos nao tem especificacao
      end;
      select coalesce(array_agg(x->>'code'), '{}') into v_fn_codes
        from jsonb_array_elements(coalesce(spec->'functions', '[]'::jsonb)) x;

      for s in select * from jsonb_array_elements(coalesce(spec->'status', '[]'::jsonb)) loop
        v_vals := case when coalesce(s->>'values', '') = '' then '{}'::jsonb else (s->>'values')::jsonb end;
        v_p := v_pad -> (s->>'code');
        if v_p is not null then
          v_papel := coalesce(v_p->>'papel', 'estado'); v_gravar := coalesce((v_p->>'gravar')::boolean, false);
        elsif not ((s->>'code') = any (v_fn_codes)) then
          v_papel := 'leitura'; v_gravar := true;
        elsif s->>'type' = 'Boolean' then
          v_papel := 'leitura'; v_gravar := true;
        else
          v_papel := 'config'; v_gravar := false;
        end if;
        insert into iot.grandezas (dispositivo_id, codigo, nome, tipo_valor, unidade, escala, faixa, papel, gravar, comandavel, bloqueada)
        values (v_did, s->>'code', coalesce(v_p->>'nome', s->>'code'), s->>'type', v_vals->>'unit',
                coalesce((v_vals->>'scale')::int, 0), v_vals, v_papel, v_gravar, (s->>'code') = any (v_fn_codes),
                coalesce((v_p->>'bloqueada')::boolean, false))
        on conflict (dispositivo_id, codigo) do update
          set tipo_valor = excluded.tipo_valor, unidade = excluded.unidade, escala = excluded.escala, faixa = excluded.faixa,
              comandavel = iot.grandezas.comandavel or excluded.comandavel, bloqueada = excluded.bloqueada;
      end loop;
      for s in select * from jsonb_array_elements(coalesce(spec->'functions', '[]'::jsonb)) loop
        v_vals := case when coalesce(s->>'values', '') = '' then '{}'::jsonb else (s->>'values')::jsonb end;
        v_p := v_pad -> (s->>'code');
        insert into iot.grandezas (dispositivo_id, codigo, nome, tipo_valor, unidade, escala, faixa, papel, gravar, comandavel, bloqueada)
        values (v_did, s->>'code', coalesce(v_p->>'nome', s->>'code'), s->>'type', v_vals->>'unit',
                coalesce((v_vals->>'scale')::int, 0), v_vals, coalesce(v_p->>'papel', 'config'),
                coalesce((v_p->>'gravar')::boolean, false), true, coalesce((v_p->>'bloqueada')::boolean, false))
        on conflict (dispositivo_id, codigo) do update set comandavel = true, bloqueada = excluded.bloqueada;
      end loop;
      -- grandezas derivadas (ex.: fases do medidor trifasico)
      perform iot.grandezas_de_padrao(v_did, v_pad, true, false);
      n := n + 1;
    end loop;
    exit when not coalesce((r->>'has_more')::boolean, false);
    v_lrk := coalesce(r->>'last_row_key', '');
  end loop;

  -- controles virtuais dos hubs IR: viram dispositivos filhos
  for hub in select id, id_externo, online, local_id from iot.dispositivos where fonte_id = f.id and categoria = 'wnykq' and ativo loop
    begin
      r := iot.tuya_request(f, 'GET', '/v2.0/infrareds/' || hub.id_externo || '/remotes');
    exception when others then
      r := '[]'::jsonb;
    end;
    for rem in select * from jsonb_array_elements(case when jsonb_typeof(r) = 'array' then r else '[]'::jsonb end) loop
      v_rem_cat := case when (rem->>'category_id') = '5' then 'infrared_ac' else 'infrared_' || coalesce(rem->>'category_id', 'x') end;
      select id, grandezas_padrao into v_rem_tipo, v_rem_pad from iot.tipos_dispositivo where codigo = 'tuya:' || v_rem_cat;
      insert into iot.dispositivos (cliente_id, fonte_id, tipo_id, id_externo, nome, produto, categoria, alimentacao, online, pai_id, local_id)
      values (f.cliente_id, f.id, v_rem_tipo, rem->>'remote_id', coalesce(rem->>'remote_name', 'Controle ' || (rem->>'remote_id')),
              coalesce(rem->>'brand_name', 'IR'), v_rem_cat, 'rede', hub.online, hub.id, hub.local_id)
      on conflict (fonte_id, id_externo) do update
        set pai_id = excluded.pai_id, categoria = excluded.categoria, produto = excluded.produto,
            tipo_id = coalesce(iot.dispositivos.tipo_id, excluded.tipo_id), atualizado_em = now()
      returning id into v_did;
      if v_rem_cat = 'infrared_ac' then
        perform iot.grandezas_de_padrao(v_did, v_rem_pad, false, true);
      end if;
      n := n + 1;
    end loop;
  end loop;

  update iot.fontes set ultima_sincronizacao_em = now() where id = p_fonte_id;
  return n;
end $$;

-- ---------- coleta: leituras derivadas e estado dos controles IR ----------
create or replace function iot.coletar(p_fonte_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'iot', 'extensions', 'public' as $$
declare
  f iot.fontes; r jsonb; d jsonb; s jsonb; v_disp iot.dispositivos; v_g iot.grandezas; v_ult iot.leituras;
  v_val numeric; v_txt text; v_estado jsonb; v_der jsonb; v_mudou boolean; v_tinha boolean; v_diff boolean;
  v_lrk text; v_gravadas int; v_disp_n int; v_res jsonb := '[]'::jsonb; v_agora timestamptz := now();
  v_k text; v_v jsonb; rem record; v_ir jsonb;
begin
  for f in select * from iot.fontes where ativa and tipo = 'tuya' and (p_fonte_id is null or id = p_fonte_id) loop
    begin
      f := iot.tuya_token(f.id);
      v_lrk := ''; v_gravadas := 0; v_disp_n := 0;
      loop
        r := iot.tuya_request(f, 'GET', '/v1.0/iot-01/associated-users/devices', 'last_row_key=' || v_lrk || '&size=100');
        for d in select * from jsonb_array_elements(coalesce(r->'devices', '[]'::jsonb)) loop
          select * into v_disp from iot.dispositivos where fonte_id = f.id and id_externo = d->>'id';
          if not found or not v_disp.ativo then continue; end if;
          v_disp_n := v_disp_n + 1;
          v_estado := '{}'::jsonb; v_mudou := false;
          for s in select * from jsonb_array_elements(coalesce(d->'status', '[]'::jsonb)) loop
            select * into v_g from iot.grandezas where dispositivo_id = v_disp.id and codigo = s->>'code';
            if not found then continue; end if;
            v_val := null; v_txt := null;
            case jsonb_typeof(s->'value')
              when 'number'  then v_val := (s->>'value')::numeric / power(10::numeric, v_g.escala);
              when 'boolean' then v_val := case when (s->>'value')::boolean then 1 else 0 end;
              else v_txt := s->>'value';
            end case;
            v_estado := v_estado || jsonb_build_object(v_g.codigo,
                          case when jsonb_typeof(s->'value') = 'boolean' then s->'value' else coalesce(to_jsonb(v_val), to_jsonb(v_txt)) end);
            if v_g.gravar then
              select * into v_ult from iot.leituras
               where dispositivo_id = v_disp.id and codigo = v_g.codigo order by instante desc limit 1;
              v_tinha := found;
              v_diff := (not v_tinha) or v_ult.valor is distinct from v_val or v_ult.valor_texto is distinct from v_txt;
              if v_diff or v_ult.instante < v_agora - interval '60 minutes' then
                insert into iot.leituras (dispositivo_id, codigo, valor, valor_texto, instante)
                values (v_disp.id, v_g.codigo, v_val, v_txt, v_agora);
                v_gravadas := v_gravadas + 1;
              end if;
              if v_diff then v_mudou := true; end if;
            end if;
          end loop;
          -- leituras derivadas (medidor trifasico)
          v_der := iot.derivadas(v_disp.categoria, v_estado);
          for v_k, v_v in select * from jsonb_each(v_der) loop
            select * into v_g from iot.grandezas where dispositivo_id = v_disp.id and codigo = v_k;
            if not found or not v_g.gravar then continue; end if;
            v_val := (v_v #>> '{}')::numeric;
            select * into v_ult from iot.leituras where dispositivo_id = v_disp.id and codigo = v_k order by instante desc limit 1;
            v_tinha := found;
            v_diff := (not v_tinha) or v_ult.valor is distinct from v_val;
            if v_diff or v_ult.instante < v_agora - interval '60 minutes' then
              insert into iot.leituras (dispositivo_id, codigo, valor, instante) values (v_disp.id, v_k, v_val, v_agora);
              v_gravadas := v_gravadas + 1;
            end if;
            if v_diff then v_mudou := true; end if;
          end loop;
          v_estado := v_estado || v_der;
          update iot.dispositivos set
            estado_atual = v_estado,
            online = (d->>'online')::boolean,
            online_desde = case when (d->>'online')::boolean and online is distinct from true then v_agora else online_desde end,
            ultima_leitura_em = v_agora,
            ultima_mudanca_em = case when v_mudou then v_agora else ultima_mudanca_em end,
            nome = coalesce(d->>'name', nome),
            atualizado_em = v_agora
          where id = v_disp.id;
          perform iot.eventos_dispositivo(v_disp.id);
        end loop;
        exit when not coalesce((r->>'has_more')::boolean, false);
        v_lrk := coalesce(r->>'last_row_key', '');
      end loop;

      -- controles IR: estado presumido consultado na nuvem a cada N min (padrao 60) para captar mudancas feitas no app
      for rem in
        select c.*, h.id_externo as hub_ext, h.online as hub_online
          from iot.dispositivos c join iot.dispositivos h on h.id = c.pai_id
         where c.fonte_id = f.id and c.ativo and c.categoria = 'infrared_ac' and h.ativo
           and (c.ultima_leitura_em is null
                or c.ultima_leitura_em < v_agora - make_interval(mins => coalesce((c.parametros->>'consultar_min')::int, 60)))
      loop
        begin
          v_ir := iot.tuya_request(f, 'GET', '/v2.0/infrareds/' || rem.hub_ext || '/remotes/' || rem.id_externo || '/ac/status');
          v_estado := '{}'::jsonb; v_mudou := false;
          for v_k, v_v in select * from jsonb_each(coalesce(v_ir, '{}'::jsonb)) loop
            select * into v_g from iot.grandezas where dispositivo_id = rem.id and codigo = v_k;
            if not found then continue; end if;
            v_val := nullif(regexp_replace(v_v #>> '{}', '[^0-9.-]', '', 'g'), '')::numeric;
            if v_val is null then continue; end if;
            v_estado := v_estado || jsonb_build_object(v_k, v_val);
            if v_g.gravar then
              select * into v_ult from iot.leituras where dispositivo_id = rem.id and codigo = v_k order by instante desc limit 1;
              v_tinha := found;
              v_diff := (not v_tinha) or v_ult.valor is distinct from v_val;
              if v_diff or v_ult.instante < v_agora - interval '60 minutes' then
                insert into iot.leituras (dispositivo_id, codigo, valor, instante) values (rem.id, v_k, v_val, v_agora);
                v_gravadas := v_gravadas + 1;
              end if;
              if v_diff then v_mudou := true; end if;
            end if;
          end loop;
          update iot.dispositivos set estado_atual = estado_atual || v_estado, online = rem.hub_online,
                 ultima_leitura_em = v_agora, ultima_mudanca_em = case when v_mudou then v_agora else ultima_mudanca_em end,
                 atualizado_em = v_agora
           where id = rem.id;
          v_disp_n := v_disp_n + 1;
        exception when others then
          -- nao martelar a API: marca a consulta e segue; falha persistente aparece em eventos pelo comando
          update iot.dispositivos set ultima_leitura_em = v_agora, online = rem.hub_online where id = rem.id;
        end;
      end loop;

      update iot.fontes set ultima_coleta_em = v_agora, ultimo_erro = null where id = f.id;
      update iot.eventos set status = 'fechado', fechado_em = v_agora
       where tipo = 'erro_fonte' and status <> 'fechado' and detalhe->>'fonte_id' = f.id::text;
      v_res := v_res || jsonb_build_object('fonte', f.nome, 'dispositivos', v_disp_n, 'leituras_gravadas', v_gravadas);
    exception when others then
      update iot.fontes set ultimo_erro = sqlerrm, ultimo_erro_em = v_agora where id = f.id;
      if not exists (select 1 from iot.eventos where tipo = 'erro_fonte' and status <> 'fechado' and detalhe->>'fonte_id' = f.id::text) then
        insert into iot.eventos (cliente_id, tipo, severidade, titulo, detalhe)
        values (f.cliente_id, 'erro_fonte', 'critico', 'Falha de comunicacao com ' || f.nome,
                jsonb_build_object('fonte_id', f.id, 'erro', sqlerrm));
      end if;
      v_res := v_res || jsonb_build_object('fonte', f.nome, 'erro', sqlerrm);
    end;
  end loop;
  perform iot.avaliar_regras();
  perform iot.aplicar_agendas();
  return v_res;
end $$;

-- ---------- agendas: alvo por zona e partida escalonada ----------
create or replace function iot.aplicar_agendas()
returns integer language plpgsql security definer set search_path to 'iot', 'public' as $$
declare a iot.agendas; a_eff iot.agendas; d record; v_on boolean; v_desejado jsonb; v_atual jsonb; e iot.agenda_estado; n int := 0;
begin
  for a in select * from iot.agendas where ativa loop
    for d in
      select dv.id, dv.estado_atual, dv.nome, l.fuso,
             coalesce((select min(z.ordem) from iot.zona_dispositivos zd join iot.zonas z on z.id = zd.zona_id
                        where zd.dispositivo_id = dv.id and (a.zona_id is null or z.id = a.zona_id)), 1) as ordem
        from iot.dispositivos dv
        left join iot.locais l on l.id = dv.local_id
       where dv.cliente_id = a.cliente_id and dv.ativo and dv.online is not false
         and (a.local_id is null or dv.local_id = a.local_id)
         and (a.dispositivo_id is null or dv.id = a.dispositivo_id)
         and (a.zona_id is null or exists (select 1 from iot.zona_dispositivos zd where zd.zona_id = a.zona_id and zd.dispositivo_id = dv.id))
         and exists (select 1 from iot.grandezas g where g.dispositivo_id = dv.id and g.codigo = a.codigo and g.comandavel and not g.bloqueada)
       order by ordem, dv.nome
    loop
      -- partida escalonada: a zona de ordem k liga (k-1) x escalonar_min depois; o desligamento e o mesmo para todos
      a_eff := a;
      if a.escalonar_min > 0 and d.ordem > 1 then
        a_eff.hora_ligar := (a.hora_ligar + make_interval(mins => (d.ordem - 1) * a.escalonar_min))::time;
      end if;
      v_on := iot.agenda_ligada(a_eff, d.fuso);
      v_desejado := case when v_on then a.valor_ligar else a.valor_desligar end;
      v_atual := d.estado_atual -> a.codigo;
      select * into e from iot.agenda_estado where agenda_id = a.id and dispositivo_id = d.id and codigo = a.codigo;
      if v_atual is distinct from v_desejado
         and (not found or e.ultimo_valor is distinct from v_desejado or e.ultimo_comando_em < now() - make_interval(mins => a.reenviar_min)) then
        perform iot.comandar(d.id, a.codigo, v_desejado, 'agenda: ' || a.nome, null);
        insert into iot.agenda_estado (agenda_id, dispositivo_id, codigo, ultimo_valor, ultimo_comando_em)
        values (a.id, d.id, a.codigo, v_desejado, now())
        on conflict (agenda_id, dispositivo_id, codigo) do update set ultimo_valor = excluded.ultimo_valor, ultimo_comando_em = excluded.ultimo_comando_em;
        n := n + 1;
      end if;
      if v_on and a.setpoint_codigo is not null and a.setpoint_valor is not null
         and exists (select 1 from iot.grandezas g where g.dispositivo_id = d.id and g.codigo = a.setpoint_codigo and g.comandavel and not g.bloqueada) then
        v_atual := d.estado_atual -> a.setpoint_codigo;
        select * into e from iot.agenda_estado where agenda_id = a.id and dispositivo_id = d.id and codigo = a.setpoint_codigo;
        if v_atual is distinct from a.setpoint_valor
           and (not found or e.ultimo_valor is distinct from a.setpoint_valor or e.ultimo_comando_em < now() - make_interval(mins => a.reenviar_min)) then
          perform iot.comandar(d.id, a.setpoint_codigo, a.setpoint_valor, 'agenda (setpoint): ' || a.nome, null);
          insert into iot.agenda_estado (agenda_id, dispositivo_id, codigo, ultimo_valor, ultimo_comando_em)
          values (a.id, d.id, a.setpoint_codigo, a.setpoint_valor, now())
          on conflict (agenda_id, dispositivo_id, codigo) do update set ultimo_valor = excluded.ultimo_valor, ultimo_comando_em = excluded.ultimo_comando_em;
          n := n + 1;
        end if;
      end if;
    end loop;
  end loop;
  return n;
end $$;
