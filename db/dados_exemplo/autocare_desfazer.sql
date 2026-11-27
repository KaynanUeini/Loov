-- ============================================================================
-- Desfaz os dados de exemplo do "Auto Care AB" (só se precisar).
-- Apaga as avaliações e os agendamentos dos clientes de teste, os avulsos
-- lançados pelo script, os custos mensais que ele criou e os 30 clientes de
-- teste. Não mexe no lava-rápido, nos serviços nem no horário.
-- ============================================================================
DO $$
DECLARE cw_id bigint;
BEGIN
  SELECT id INTO cw_id FROM car_washes WHERE name ILIKE 'auto care ab%' ORDER BY id DESC LIMIT 1;
  IF cw_id IS NULL THEN RAISE EXCEPTION 'Não achei o lava-rápido "Auto Care AB".'; END IF;

  DELETE FROM reviews WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'cliente.teste%@loov.dev');
  DELETE FROM appointments
   WHERE car_wash_id = cw_id
     AND (user_id IN (SELECT id FROM users WHERE email LIKE 'cliente.teste%@loov.dev')
          OR (walk_in AND created_at = scheduled_at AND scheduled_at < date '2026-11-27'));
  DELETE FROM monthly_costs
   WHERE car_wash_id = cw_id AND year = 2026 AND month BETWEEN 5 AND 11
     AND EXTRACT(HOUR FROM created_at) = 15 AND EXTRACT(DAY FROM created_at) IN (25, 28);
  DELETE FROM users WHERE email LIKE 'cliente.teste%@loov.dev'
     AND NOT EXISTS (SELECT 1 FROM appointments a WHERE a.user_id = users.id);
  RAISE NOTICE 'Dados de exemplo apagados.';
END $$;
