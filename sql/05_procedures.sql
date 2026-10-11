SET search_path = fleet, public;

-- vehicles

CREATE OR REPLACE PROCEDURE sp_vehicle_create(
    p_user_id integer,
    p_model_id integer,
    p_department_id integer,
    p_plate_number varchar,
    p_vin varchar,
    p_manufacture_year integer,
    p_color varchar,
    p_odometer_km integer,
    p_purchase_date date,
    p_purchase_price numeric,
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    INSERT INTO vehicles (model_id, department_id, plate_number, vin, manufacture_year, color, odometer_km, purchase_date, purchase_price)
    VALUES (p_model_id, p_department_id, upper(p_plate_number), upper(p_vin), p_manufacture_year, p_color,
            coalesce(p_odometer_km, 0), p_purchase_date, p_purchase_price)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_vehicle_update(
    p_user_id integer,
    p_id integer,
    p_department_id integer,
    p_plate_number varchar,
    p_color varchar,
    p_odometer_km integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE vehicles
    SET department_id = coalesce(p_department_id, department_id),
        plate_number = coalesce(upper(p_plate_number), plate_number),
        color = coalesce(p_color, color),
        odometer_km = coalesce(p_odometer_km, odometer_km)
    WHERE id = p_id AND NOT is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle with id % not found', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_vehicle_delete(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status vehicle_status;
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    SELECT status INTO v_status FROM vehicles WHERE id = p_id AND NOT is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle with id % not found', p_id;
    END IF;
    IF v_status IN ('on_trip', 'in_service') THEN
        RAISE EXCEPTION 'Vehicle is on a trip or in service, it can not be deleted';
    END IF;

    UPDATE trips SET status = 'cancelled', notes = 'Cancelled: vehicle deleted'
    WHERE vehicle_id = p_id AND status = 'planned';
    UPDATE vehicle_assignments SET assigned_to = current_date
    WHERE vehicle_id = p_id AND (assigned_to IS NULL OR assigned_to > current_date);

    -- trg_vehicles_soft_delete turns this into soft delete
    DELETE FROM vehicles WHERE id = p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_vehicle_restore(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE vehicles SET is_deleted = false, deleted_at = NULL, deleted_by = NULL
    WHERE id = p_id AND is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deleted vehicle with id % not found', p_id;
    END IF;
END;
$$;

-- drivers

CREATE OR REPLACE PROCEDURE sp_driver_create(
    p_user_id integer,
    p_department_id integer,
    p_last_name varchar,
    p_first_name varchar,
    p_middle_name varchar,
    p_birth_date date,
    p_phone varchar,
    p_email varchar,
    p_license_number varchar,
    p_license_expiry date,
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    INSERT INTO drivers (department_id, last_name, first_name, middle_name, birth_date, phone, email, license_number, license_expiry)
    VALUES (p_department_id, p_last_name, p_first_name, p_middle_name, p_birth_date, p_phone, p_email,
            upper(p_license_number), p_license_expiry)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_driver_update(
    p_user_id integer,
    p_id integer,
    p_department_id integer,
    p_phone varchar,
    p_email varchar,
    p_license_number varchar,
    p_license_expiry date)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE drivers
    SET department_id = coalesce(p_department_id, department_id),
        phone = coalesce(p_phone, phone),
        email = coalesce(p_email, email),
        license_number = coalesce(upper(p_license_number), license_number),
        license_expiry = coalesce(p_license_expiry, license_expiry)
    WHERE id = p_id AND NOT is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Driver with id % not found', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_driver_add_license(
    p_user_id integer,
    p_driver_id integer,
    p_category_code varchar,
    p_obtained_date date)
LANGUAGE plpgsql
AS $$
DECLARE
    v_category_id smallint;
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    SELECT id INTO v_category_id FROM license_categories WHERE code = upper(p_category_code);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'License category % does not exist', p_category_code;
    END IF;
    INSERT INTO driver_licenses (driver_id, category_id, obtained_date)
    VALUES (p_driver_id, v_category_id, p_obtained_date)
    ON CONFLICT (driver_id, category_id) DO UPDATE SET obtained_date = EXCLUDED.obtained_date;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_driver_delete(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    IF NOT EXISTS (SELECT 1 FROM drivers WHERE id = p_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Driver with id % not found', p_id;
    END IF;
    IF EXISTS (SELECT 1 FROM trips WHERE driver_id = p_id AND status = 'in_progress') THEN
        RAISE EXCEPTION 'Driver is on a trip, it can not be deleted';
    END IF;

    UPDATE trips SET status = 'cancelled', notes = 'Cancelled: driver deleted'
    WHERE driver_id = p_id AND status = 'planned';
    UPDATE vehicle_assignments SET assigned_to = current_date
    WHERE driver_id = p_id AND (assigned_to IS NULL OR assigned_to > current_date);

    DELETE FROM drivers WHERE id = p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_driver_restore(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE drivers SET is_deleted = false, deleted_at = NULL, deleted_by = NULL
    WHERE id = p_id AND is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deleted driver with id % not found', p_id;
    END IF;
END;
$$;

-- assign vehicle to driver, previous assignment of the vehicle gets closed
CREATE OR REPLACE PROCEDURE sp_vehicle_assign(
    p_user_id integer,
    p_vehicle_id integer,
    p_driver_id integer,
    p_from date DEFAULT current_date)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    IF NOT fn_driver_can_drive(p_driver_id, p_vehicle_id, p_from) THEN
        RAISE EXCEPTION 'Driver can not drive this vehicle (category or license)';
    END IF;
    UPDATE vehicle_assignments SET assigned_to = p_from - 1
    WHERE vehicle_id = p_vehicle_id AND assigned_from < p_from AND (assigned_to IS NULL OR assigned_to >= p_from);
    INSERT INTO vehicle_assignments (vehicle_id, driver_id, assigned_from, created_by)
    VALUES (p_vehicle_id, p_driver_id, p_from, p_user_id);
END;
$$;

-- trips

CREATE OR REPLACE PROCEDURE sp_trip_plan(
    p_user_id integer,
    p_vehicle_id integer,
    p_driver_id integer,
    p_route_id integer,
    p_purpose varchar,
    p_planned_start timestamptz,
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    INSERT INTO trips (vehicle_id, driver_id, route_id, purpose, planned_start)
    VALUES (p_vehicle_id, p_driver_id, p_route_id, p_purpose, p_planned_start)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_trip_start(p_user_id integer, p_trip_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    -- start odometer and vehicle status are set by triggers
    UPDATE trips SET status = 'in_progress', actual_start = now()
    WHERE id = p_trip_id AND status = 'planned';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Planned trip with id % not found', p_trip_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_trip_complete(
    p_user_id integer,
    p_trip_id integer,
    p_end_odometer integer,
    p_notes text DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE trips
    SET status = 'completed',
        actual_end = now(),
        end_odometer = p_end_odometer,
        notes = coalesce(p_notes, notes)
    WHERE id = p_trip_id AND status = 'in_progress';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active trip with id % not found', p_trip_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_trip_cancel(p_user_id integer, p_trip_id integer, p_reason text)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE trips
    SET status = 'cancelled',
        actual_end = CASE WHEN status = 'in_progress' THEN now() END,
        notes = p_reason
    WHERE id = p_trip_id AND status IN ('planned', 'in_progress');
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip with id % can not be cancelled', p_trip_id;
    END IF;
END;
$$;

-- fuel

CREATE OR REPLACE PROCEDURE sp_fuel_record_add(
    p_user_id integer,
    p_vehicle_id integer,
    p_driver_id integer,
    p_liters numeric,
    p_price_per_liter numeric,
    p_station varchar,
    p_refuel_date timestamptz DEFAULT now(),
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    -- fuel type and odometer are filled by trigger
    INSERT INTO fuel_records (vehicle_id, driver_id, liters, price_per_liter, station, refuel_date)
    VALUES (p_vehicle_id, p_driver_id, p_liters, p_price_per_liter, p_station, coalesce(p_refuel_date, now()))
    RETURNING id INTO p_id;
END;
$$;

-- maintenance

CREATE OR REPLACE PROCEDURE sp_maintenance_schedule(
    p_user_id integer,
    p_vehicle_id integer,
    p_service_center_id integer,
    p_maintenance_type_id integer,
    p_scheduled_date date,
    p_description text,
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    IF EXISTS (SELECT 1 FROM vehicles WHERE id = p_vehicle_id AND is_deleted) THEN
        RAISE EXCEPTION 'Vehicle with id % is deleted', p_vehicle_id;
    END IF;
    INSERT INTO maintenance_records (vehicle_id, service_center_id, maintenance_type_id, scheduled_date, description)
    VALUES (p_vehicle_id, p_service_center_id, p_maintenance_type_id, p_scheduled_date, p_description)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_maintenance_start(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE maintenance_records m
    SET status = 'in_progress',
        started_at = now(),
        odometer_km = v.odometer_km
    FROM vehicles v
    WHERE m.id = p_id AND v.id = m.vehicle_id AND m.status = 'scheduled' AND NOT m.is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Scheduled maintenance with id % not found', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_maintenance_complete(
    p_user_id integer,
    p_id integer,
    p_cost numeric,
    p_description text DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE maintenance_records
    SET status = 'completed',
        completed_at = now(),
        cost = p_cost,
        description = coalesce(p_description, description)
    WHERE id = p_id AND status = 'in_progress' AND NOT is_deleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active maintenance with id % not found', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_maintenance_delete(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    IF EXISTS (SELECT 1 FROM maintenance_records WHERE id = p_id AND status = 'in_progress') THEN
        RAISE EXCEPTION 'Maintenance is in progress, complete it first';
    END IF;
    DELETE FROM maintenance_records WHERE id = p_id;
END;
$$;

-- fines

CREATE OR REPLACE PROCEDURE sp_fine_register(
    p_user_id integer,
    p_vehicle_id integer,
    p_violation_at timestamptz,
    p_description varchar,
    p_amount numeric,
    INOUT p_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip_id integer;
    v_driver_id integer;
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    -- driver is taken from the trip active at the violation time
    SELECT id, driver_id INTO v_trip_id, v_driver_id
    FROM trips
    WHERE vehicle_id = p_vehicle_id
      AND actual_start <= p_violation_at
      AND coalesce(actual_end, 'infinity') >= p_violation_at
    ORDER BY actual_start DESC
    LIMIT 1;

    INSERT INTO fines (vehicle_id, driver_id, trip_id, violation_at, description, amount)
    VALUES (p_vehicle_id, v_driver_id, v_trip_id, p_violation_at, p_description, p_amount)
    RETURNING id INTO p_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_fine_pay(p_user_id integer, p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_current_user(p_user_id);
    UPDATE fines SET is_paid = true, paid_at = now() WHERE id = p_id AND NOT is_paid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unpaid fine with id % not found', p_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_refresh_statistics()
LANGUAGE sql
AS $$
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_department_monthly_stats;
$$;

-- table functions for reading
-- available vehicles the driver is allowed to drive
CREATE OR REPLACE FUNCTION fn_available_vehicles(p_driver_id integer)
RETURNS SETOF v_vehicles
LANGUAGE sql STABLE
AS $$
    SELECT v.*
    FROM v_vehicles v
    WHERE v.status = 'available'
      AND fn_driver_can_drive(p_driver_id, v.id)
    ORDER BY v.plate_number
$$;

-- driver trips for a period
CREATE OR REPLACE FUNCTION fn_driver_trips(p_driver_id integer, p_from date, p_to date)
RETURNS SETOF v_trips
LANGUAGE sql STABLE
AS $$
    SELECT *
    FROM v_trips
    WHERE driver_id = p_driver_id
      AND planned_start >= p_from AND planned_start < p_to + 1
    ORDER BY planned_start DESC
$$;
