-- ============================================================================
-- Dados de exemplo do lava-rápido "Auto Care AB" (maio até hoje)
-- Resultado "bom moderado": ~R$ 18 mil em maio subindo para ~R$ 22 mil/mês,
-- custos de ~R$ 14 mil/mês, nota média ~4,5, clientes recorrentes, avulsos e
-- Last Minute. Cria 30 clientes de teste (cliente.teste01..30@loov.dev, sem
-- senha: ninguém entra com eles).
--
-- Como rodar: cole tudo no SQL Editor do Neon e clique em Run. Ele acha o
-- lava-rápido pelo nome; se já tiver rodado antes, para sem duplicar nada.
-- ============================================================================
DO $$
DECLARE
  cw_id     bigint;
  svc_ids   bigint[];
  svc_price numeric[];
  svc_dur   int[];
  n_svc     int;
  dias_abertos int[];
  cli_ids   bigint[];
  nomes     text[] := ARRAY['Rafael Souza','Camila Rocha','Bruno Almeida','Juliana Costa','Thiago Martins','Fernanda Lima','Lucas Pereira','Patrícia Gomes','Diego Ribeiro','Aline Carvalho','Marcelo Nunes','Bianca Teixeira','Gustavo Araújo','Larissa Mendes','Felipe Barros','Renata Freitas','André Cardoso','Vanessa Pinto','Rodrigo Moreira','Tatiane Dias','Eduardo Ramos','Priscila Castro','Leandro Correia','Natália Vieira','Fábio Monteiro','Carolina Batista','Ricardo Lopes','Daniela Farias','Vinícius Rezende','Mariana Duarte'];
  carros    text[] := ARRAY['HB20','Onix','Gol','Corolla','Compass','T-Cross','Kicks','Civic','Polo','Creta','HR-V','Argo','Renegade','Tracker','Hilux','Strada','Ka','Sandero','Fit','Virtus'];
  avulsos   text[] := ARRAY['Avulso','Seu Antônio','Kombi do mercado','Dona Cida','Uber do bairro','Avulso','Moto do Júnior','Avulso','Táxi 12','Avulso'];
  coment5   text[] := ARRAY['Carro ficou impecável, atendimento nota 10.','Rápido e caprichado. Já virei cliente.','Melhor lava-rápido da região, recomendo.','Pessoal muito atencioso, entregaram no horário.','Ficou brilhando, até o pretinho do pneu ficou top.',''];
  coment4   text[] := ARRAY['Bom serviço, só demorou um pouco mais que o previsto.','Ficou bem limpo, faltou só caprichar no vidro.','Gostei, preço justo.','Atendimento bom, voltarei.',''];
  coment3   text[] := ARRAY['Ok, mas esperei bastante.','Limpeza razoável, esqueceram o porta-malas.',''];
  coment2   text[] := ARRAY['Demorou muito e o interior ficou com poeira.'];
  tags5     text[] := ARRAY['Limpeza impecável','Atendimento rápido','Ótimo preço','Equipe simpática','Fácil de agendar'];
  d         date;
  hoje      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  agora     timestamp := now() AT TIME ZONE 'UTC';
  mes_idx   int;
  alvo      numeric;
  soma      numeric;
  k         int;
  pr        numeric;
  dur       int;
  sid       bigint;
  uid       bigint;
  quando    timestamp;
  tipo      text;
  st        text;
  walk      boolean;
  ap_id     bigint;
  nota      int;
  r         float;
  com       text;
  tg        text;
  i         int;
BEGIN
  SELECT id INTO cw_id FROM car_washes WHERE name ILIKE 'auto care ab%' ORDER BY id DESC LIMIT 1;
  IF cw_id IS NULL THEN RAISE EXCEPTION 'Não achei o lava-rápido "Auto Care AB". Confira o nome.'; END IF;

  SELECT array_agg(id ORDER BY price), array_agg(price ORDER BY price), array_agg(COALESCE(duration, 40) ORDER BY price)
    INTO svc_ids, svc_price, svc_dur
    FROM services WHERE car_wash_id = cw_id AND price > 0;
  n_svc := COALESCE(array_length(svc_ids, 1), 0);
  IF n_svc = 0 THEN RAISE EXCEPTION 'O Auto Care AB não tem serviços com preço. Cadastre os serviços antes.'; END IF;

  IF EXISTS (SELECT 1 FROM appointments a JOIN users u ON u.id = a.user_id
             WHERE a.car_wash_id = cw_id AND u.email LIKE 'cliente.teste%@loov.dev') THEN
    RAISE NOTICE 'Os dados de exemplo já existem neste lava-rápido. Nada foi feito.';
    RETURN;
  END IF;

  -- Dias abertos: os do horário de funcionamento; sem horário, segunda a sábado.
  SELECT array_agg(DISTINCT day_of_week) INTO dias_abertos FROM operating_hours WHERE car_wash_id = cw_id;
  IF dias_abertos IS NULL THEN dias_abertos := ARRAY[1,2,3,4,5,6]; END IF;

  -- 30 clientes de teste
  FOR i IN 1..30 LOOP
    INSERT INTO users (email, encrypted_password, role, full_name, phone, vehicle_model, vehicle_plate, created_at, updated_at)
    VALUES ('cliente.teste' || lpad(i::text, 2, '0') || '@loov.dev', '', 'client', nomes[i],
            '(11) 9' || lpad((80000000 + i * 137911)::text, 8, '0'),
            carros[1 + (i % array_length(carros, 1))],
            chr(65 + (i % 26)) || chr(66 + (i * 7 % 24)) || chr(67 + (i * 3 % 23)) || (i % 10)::text || chr(65 + (i * 5 % 26)) || lpad((i * 13 % 100)::text, 2, '0'),
            timestamp '2026-04-10 12:00' + (i || ' days')::interval, timestamp '2026-04-10 12:00' + (i || ' days')::interval)
    ON CONFLICT (email) DO NOTHING;
  END LOOP;
  SELECT array_agg(id ORDER BY email) INTO cli_ids FROM users WHERE email LIKE 'cliente.teste%@loov.dev';

  d := date '2026-05-01';
  WHILE d <= hoje + 1 LOOP
    IF EXTRACT(DOW FROM d)::int = ANY (dias_abertos) THEN
      mes_idx := (EXTRACT(YEAR FROM d)::int - 2026) * 12 + EXTRACT(MONTH FROM d)::int - 5;
      alvo := (15600 + mes_idx * 600) / 26.0 * (0.78 + random() * 0.42);
      IF EXTRACT(DOW FROM d) = 6 THEN alvo := alvo * 1.3; END IF;
      IF EXTRACT(DOW FROM d) = 1 THEN alvo := alvo * 0.85; END IF;
      IF d > hoje THEN alvo := alvo * 0.4; END IF;   -- amanhã: só o que já foi agendado
      soma := 0;
      WHILE soma < alvo LOOP
        k   := 1 + floor(n_svc * power(random(), 1.7))::int;
        IF k > n_svc THEN k := n_svc; END IF;
        sid := svc_ids[k]; pr := svc_price[k]; dur := svc_dur[k];
        -- 8h às 17h30 em Brasília (UTC-3), de meia em meia hora
        quando := d + time '11:00' + (floor(random() * 20) * 30 || ' minutes')::interval;
        r := random();
        IF r < 0.33 THEN walk := true; tipo := 'regular';
        ELSIF r < 0.43 THEN walk := false; tipo := 'disponivel';
        ELSE walk := false; tipo := 'regular';
        END IF;
        IF walk AND quando > agora THEN CONTINUE; END IF;  -- avulso só no passado

        IF quando > agora THEN
          st := 'confirmed';
        ELSE
          r := random();
          st := CASE WHEN walk THEN 'attended' WHEN r < 0.05 THEN 'cancelled' WHEN r < 0.08 THEN 'no_show' ELSE 'attended' END;
        END IF;
        uid := CASE WHEN walk THEN NULL ELSE cli_ids[1 + floor(30 * power(random(), 2))::int] END;

        INSERT INTO appointments (user_id, car_wash_id, service_id, scheduled_at, status, duration, walk_in, walk_in_name,
                                  appointment_type, prepayment_amount, commission_amount, attended_at,
                                  cancelled_by_role, cancellation_reason, created_at, updated_at)
        VALUES (uid, cw_id, sid, quando, st, dur, walk, CASE WHEN walk THEN avulsos[1 + floor(random() * 10)::int] END,
                tipo,
                CASE WHEN tipo = 'disponivel' THEN round(pr * 0.35, 2) END,
                CASE WHEN tipo = 'disponivel' THEN round(pr * 0.05, 2) END,
                CASE WHEN st = 'attended' THEN quando + (dur || ' minutes')::interval END,
                CASE WHEN st = 'cancelled' THEN 'client' END,
                CASE WHEN st = 'cancelled' THEN 'Imprevisto' END,
                CASE WHEN walk THEN quando WHEN tipo = 'disponivel' THEN quando - interval '20 minutes' ELSE quando - (floor(random() * 72 + 2) || ' hours')::interval END,
                CASE WHEN st = 'attended' THEN quando + (dur || ' minutes')::interval ELSE quando END)
        RETURNING id INTO ap_id;

        IF st IN ('attended', 'confirmed') THEN soma := soma + pr; END IF;

        -- Avaliação em ~40% das lavagens de clientes com conta
        IF st = 'attended' AND NOT walk AND random() < 0.4 THEN
          r := random();
          nota := CASE WHEN r < 0.66 THEN 5 WHEN r < 0.92 THEN 4 WHEN r < 0.98 THEN 3 ELSE 2 END;
          com := CASE nota WHEN 5 THEN coment5[1 + floor(random() * 6)::int] WHEN 4 THEN coment4[1 + floor(random() * 5)::int]
                           WHEN 3 THEN coment3[1 + floor(random() * 3)::int] ELSE coment2[1] END;
          tg := CASE WHEN nota >= 4 AND random() < 0.7 THEN tags5[1 + floor(random() * 5)::int] END;
          INSERT INTO reviews (appointment_id, car_wash_id, user_id, rating, tags, comment, created_at, updated_at)
          VALUES (ap_id, cw_id, uid, nota, tg, NULLIF(com, ''),
                  quando + ((dur + 60 + floor(random() * 1400)) || ' minutes')::interval,
                  quando + ((dur + 60 + floor(random() * 1400)) || ' minutes')::interval);
        END IF;
      END LOOP;
    END IF;
    d := d + 1;
  END LOOP;

  -- Custos mensais de maio a novembro (se o mês ainda não tiver)
  FOR i IN 0..6 LOOP
    IF NOT EXISTS (SELECT 1 FROM monthly_costs WHERE car_wash_id = cw_id AND year = 2026 AND month = 5 + i) THEN
      INSERT INTO monthly_costs (car_wash_id, year, month, rent, salaries, utilities, products, maintenance,
                                 other_fixed, other_variable, water, electricity, notes, created_at, updated_at)
      VALUES (cw_id, 2026, 5 + i, 3800, 6400 + CASE WHEN i >= 3 THEN 450 ELSE 0 END, 0,
              round((1450 + i * 60 + random() * 250)::numeric, 2),
              round((250 + random() * 400)::numeric, 2),
              420, round((240 + random() * 160)::numeric, 2),
              round((640 + i * 25 + random() * 120)::numeric, 2),
              round((520 + i * 15 + random() * 90)::numeric, 2),
              CASE WHEN i = 3 THEN 'Contratamos mais um lavador em agosto.' END,
              make_timestamp(2026, 5 + i, CASE WHEN i = 6 THEN 25 ELSE 28 END, 15, 0, 0), make_timestamp(2026, 5 + i, CASE WHEN i = 6 THEN 25 ELSE 28 END, 15, 0, 0));
    END IF;
  END LOOP;

  RAISE NOTICE 'Pronto: % agendamentos e % avaliações criados no lava-rápido %.',
    (SELECT count(*) FROM appointments WHERE car_wash_id = cw_id),
    (SELECT count(*) FROM reviews WHERE car_wash_id = cw_id), cw_id;
END $$;
