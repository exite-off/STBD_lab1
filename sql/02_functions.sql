SET search_path = fleet, public;

-- get current transaction's user id
CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS integer
LANGUAGE sql STABLE
AS $$
    SELECT nullif(current_setting('app.user_id', true), '')::integer
$$;

CREATE OR REPLACE FUNCTION fn_set_current_user(p_user_id integer)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'There is no user with id %', p_user_id;
    END IF;
    PERFORM set_config('app.user_id', p_user_id::text, true);
END;
$$;

-- check for driver license and category
CREATE OR REPLACE FUNCTION fn_driver_can_drive(p_driver_id integer, p_vehicle_id integer, p_on date DEFAULT current_date)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM drivers d
        JOIN driver_licenses dl ON dl.driver_id = d.id
        JOIN vehicles v ON v.id = p_vehicle_id
        JOIN vehicle_models m ON m.id = v.model_id
        JOIN vehicle_types t ON t.id = m.vehicle_type_id
        WHERE d.id = p_driver_id
          AND NOT d.is_deleted
          AND d.license_expiry >= p_on
          AND dl.category_id = t.required_category_id
          AND dl.obtained_date <= p_on
    )
$$;

-- fuel usage rate per period
CREATE OR REPLACE FUNCTION fn_vehicle_fuel_consumption(p_vehicle_id integer, p_from date, p_to date)
RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_liters numeric;
    v_km numeric;
BEGIN
    SELECT coalesce(sum(liters), 0) INTO v_liters
    FROM fuel_records
    WHERE vehicle_id = p_vehicle_id
      AND refuel_date >= p_from AND refuel_date < p_to + 1;

    SELECT coalesce(sum(distance_km), 0) INTO v_km
    FROM trips
    WHERE vehicle_id = p_vehicle_id
      AND status = 'completed'
      AND actual_end >= p_from AND actual_end < p_to + 1;

    IF v_km = 0 THEN
        RETURN NULL;
    END IF;
    RETURN round(v_liters / v_km * 100, 2);
END;
$$;

-- vehicle maintenance cost over period
CREATE OR REPLACE FUNCTION fn_vehicle_costs(p_vehicle_id integer, p_from date, p_to date)
RETURNS TABLE (fuel_cost numeric, maintenance_cost numeric, fines_amount numeric, insurance_cost numeric, total_cost numeric)
LANGUAGE sql STABLE
AS $$
    WITH c AS (
        SELECT
            (SELECT coalesce(sum(f.total_cost), 0) FROM fuel_records f
             WHERE f.vehicle_id = p_vehicle_id AND f.refuel_date >= p_from AND f.refuel_date < p_to + 1) AS fuel,
            (SELECT coalesce(sum(m.cost), 0) FROM maintenance_records m
             WHERE m.vehicle_id = p_vehicle_id AND NOT m.is_deleted AND m.status = 'completed'
               AND m.completed_at >= p_from AND m.completed_at < p_to + 1) AS maint,
            (SELECT coalesce(sum(fn.amount), 0) FROM fines fn
             WHERE fn.vehicle_id = p_vehicle_id AND fn.violation_at >= p_from AND fn.violation_at < p_to + 1) AS fines,
            (SELECT coalesce(sum(ip.premium), 0) FROM insurance_policies ip
             WHERE ip.vehicle_id = p_vehicle_id AND ip.start_date BETWEEN p_from AND p_to) AS ins
    )
    SELECT fuel, maint, fines, ins, fuel + maint + fines + ins FROM c
$$;

-- write history record
CREATE OR REPLACE FUNCTION fn_record_history(p_table_name varchar, p_record_id bigint)
RETURNS TABLE (changed_at timestamptz, operation varchar, changed_by varchar, changes jsonb)
LANGUAGE sql STABLE
AS $$
    SELECT a.changed_at,
           a.operation,
           coalesce(u.full_name, 'system')::varchar,
           CASE
               WHEN a.old_data IS NULL OR a.new_data IS NULL THEN coalesce(a.new_data, a.old_data)
               ELSE (
                   SELECT coalesce(jsonb_object_agg(n.key, jsonb_build_object('old', a.old_data -> n.key, 'new', n.value)), '{}')
                   FROM jsonb_each(a.new_data) n
                   WHERE a.old_data -> n.key IS DISTINCT FROM n.value
                     AND n.key NOT IN ('updated_at', 'updated_by')
               )
           END
    FROM audit_log a
    LEFT JOIN users u ON u.id = a.changed_by
    WHERE a.table_name = p_table_name AND a.record_id = p_record_id
    ORDER BY a.id
$$;
