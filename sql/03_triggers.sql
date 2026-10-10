SET search_path = fleet, public;

-- created_*/updated_* are set automatically
CREATE OR REPLACE FUNCTION trg_fn_set_audit_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
        NEW.created_by := coalesce(fn_current_user_id(), NEW.created_by);
        NEW.updated_at := NEW.created_at;
        NEW.updated_by := NEW.created_by;
    ELSE
        NEW.created_at := OLD.created_at;
        NEW.created_by := OLD.created_by;
        NEW.updated_at := now();
        NEW.updated_by := fn_current_user_id();
    END IF;
    RETURN NEW;
END;
$$;

-- DELETE becomes soft delete, for complete delete - SET app.hard_delete = 'on'
CREATE OR REPLACE FUNCTION trg_fn_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;
    IF NOT OLD.is_deleted THEN
        EXECUTE format('UPDATE %I.%I SET is_deleted = true, deleted_at = now(), deleted_by = $1 WHERE id = $2',
                       TG_TABLE_SCHEMA, TG_TABLE_NAME)
        USING fn_current_user_id(), OLD.id;
    END IF;
    RETURN NULL;
END;
$$;

-- write changes into audit log
CREATE OR REPLACE FUNCTION trg_fn_audit_log()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_op varchar(12) := TG_OP;
    v_old jsonb;
    v_new jsonb;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF v_new ? 'is_deleted' AND (v_old ->> 'is_deleted') <> (v_new ->> 'is_deleted') THEN
            v_op := CASE WHEN (v_new ->> 'is_deleted')::boolean THEN 'SOFT_DELETE' ELSE 'RESTORE' END;
        ELSIF (v_old - 'updated_at' - 'updated_by') = (v_new - 'updated_at' - 'updated_by') THEN
            RETURN NULL;
        END IF;
    END IF;

    INSERT INTO audit_log (table_name, record_id, operation, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, (coalesce(v_new, v_old) ->> 'id')::bigint, v_op, v_old, v_new, fn_current_user_id());
    RETURN NULL;
END;
$$;

-- odometer value can not decrease
CREATE OR REPLACE FUNCTION trg_fn_vehicle_odometer_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.odometer_km < OLD.odometer_km THEN
        RAISE EXCEPTION 'Odometer of vehicle % can not decrease (% -> %)', OLD.plate_number, OLD.odometer_km, NEW.odometer_km;
    END IF;
    RETURN NEW;
END;
$$;

-- checks before trip planning and start
CREATE OR REPLACE FUNCTION trg_fn_trip_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vehicle vehicles%ROWTYPE;
    v_driver drivers%ROWTYPE;
BEGIN
    SELECT * INTO v_vehicle FROM vehicles WHERE id = NEW.vehicle_id;
    SELECT * INTO v_driver FROM drivers WHERE id = NEW.driver_id;

    IF NEW.status IN ('planned', 'in_progress') AND (
        TG_OP = 'INSERT'
        OR NEW.vehicle_id <> OLD.vehicle_id
        OR NEW.driver_id <> OLD.driver_id
        OR NEW.status <> OLD.status
    ) THEN
        IF v_vehicle.is_deleted THEN
            RAISE EXCEPTION 'Vehicle % is deleted', v_vehicle.plate_number;
        END IF;
        IF v_vehicle.status IN ('in_service', 'decommissioned') THEN
            RAISE EXCEPTION 'Vehicle % is not available (status %)', v_vehicle.plate_number, v_vehicle.status;
        END IF;
        IF v_driver.is_deleted THEN
            RAISE EXCEPTION 'Driver % % is deleted', v_driver.last_name, v_driver.first_name;
        END IF;
        IF NOT fn_driver_can_drive(NEW.driver_id, NEW.vehicle_id, coalesce(NEW.actual_start, NEW.planned_start)::date) THEN
            RAISE EXCEPTION 'Driver % % has no required category for vehicle % or the license is expired',
                v_driver.last_name, v_driver.first_name, v_vehicle.plate_number;
        END IF;
    END IF;

    IF NEW.status = 'in_progress' AND (TG_OP = 'INSERT' OR OLD.status <> 'in_progress') THEN
        IF EXISTS (
            SELECT 1 FROM trips t
            WHERE t.status = 'in_progress' AND t.id <> NEW.id
              AND (t.vehicle_id = NEW.vehicle_id OR t.driver_id = NEW.driver_id)
        ) THEN
            RAISE EXCEPTION 'Vehicle % or driver is already on a trip', v_vehicle.plate_number;
        END IF;
        NEW.actual_start := coalesce(NEW.actual_start, now());
        NEW.start_odometer := coalesce(NEW.start_odometer, v_vehicle.odometer_km);
    END IF;
    RETURN NEW;
END;
$$;

-- sync vehicle status and odometer with trip status
CREATE OR REPLACE FUNCTION trg_fn_trip_status_sync()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;

    IF NEW.status = 'in_progress' THEN
        UPDATE vehicles SET status = 'on_trip' WHERE id = NEW.vehicle_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'in_progress' AND NEW.status IN ('completed', 'cancelled') THEN
        UPDATE vehicles
        SET status = 'available',
            odometer_km = greatest(odometer_km, coalesce(NEW.end_odometer, odometer_km))
        WHERE id = NEW.vehicle_id;
    END IF;
    RETURN NULL;
END;
$$;

-- vehicle status during maintenance
CREATE OR REPLACE FUNCTION trg_fn_maintenance_status_sync()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status vehicle_status;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;

    SELECT status INTO v_status FROM vehicles WHERE id = NEW.vehicle_id;

    IF NEW.status = 'in_progress' THEN
        IF v_status = 'on_trip' THEN
            RAISE EXCEPTION 'Vehicle is on a trip, maintenance can not be started';
        END IF;
        UPDATE vehicles SET status = 'in_service' WHERE id = NEW.vehicle_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'in_progress' AND NEW.status IN ('completed', 'cancelled') THEN
        IF NOT EXISTS (
            SELECT 1 FROM maintenance_records
            WHERE vehicle_id = NEW.vehicle_id AND status = 'in_progress' AND id <> NEW.id AND NOT is_deleted
        ) THEN
            UPDATE vehicles
            SET status = 'available',
                odometer_km = greatest(odometer_km, coalesce(NEW.odometer_km, odometer_km))
            WHERE id = NEW.vehicle_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

-- refuel: fuel type must match the model, volume not bigger than the tank
CREATE OR REPLACE FUNCTION trg_fn_fuel_record_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_model vehicle_models%ROWTYPE;
    v_vehicle vehicles%ROWTYPE;
BEGIN
    SELECT * INTO v_vehicle FROM vehicles WHERE id = NEW.vehicle_id;
    SELECT * INTO v_model FROM vehicle_models WHERE id = v_vehicle.model_id;

    IF v_vehicle.is_deleted THEN
        RAISE EXCEPTION 'Vehicle % is deleted', v_vehicle.plate_number;
    END IF;
    NEW.fuel_type_id := coalesce(NEW.fuel_type_id, v_model.fuel_type_id);
    IF NEW.fuel_type_id <> v_model.fuel_type_id THEN
        RAISE EXCEPTION 'Fuel type does not match the model of vehicle %', v_vehicle.plate_number;
    END IF;
    IF NEW.liters > v_model.tank_capacity THEN
        RAISE EXCEPTION 'Refuel volume % exceeds tank capacity % (%)', NEW.liters, v_model.tank_capacity, v_vehicle.plate_number;
    END IF;
    NEW.odometer_km := coalesce(NEW.odometer_km, v_vehicle.odometer_km);
    RETURN NEW;
END;
$$;

-- trigger bindings

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['vehicles', 'drivers', 'trips', 'fuel_records', 'maintenance_records', 'insurance_policies', 'fines'] LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_audit_fields BEFORE INSERT OR UPDATE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields()', t);
        EXECUTE format('CREATE TRIGGER trg_%1$s_audit_log AFTER INSERT OR UPDATE OR DELETE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_audit_log()', t);
    END LOOP;

    FOREACH t IN ARRAY ARRAY['users', 'vehicles', 'drivers', 'routes', 'service_centers', 'maintenance_records'] LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_soft_delete BEFORE DELETE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_soft_delete()', t);
    END LOOP;
END $$;

CREATE TRIGGER trg_vehicles_odometer_guard
    BEFORE UPDATE OF odometer_km ON vehicles
    FOR EACH ROW EXECUTE FUNCTION trg_fn_vehicle_odometer_guard();

CREATE TRIGGER trg_trips_validate
    BEFORE INSERT OR UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION trg_fn_trip_validate();

CREATE TRIGGER trg_trips_status_sync
    AFTER INSERT OR UPDATE OF status ON trips
    FOR EACH ROW EXECUTE FUNCTION trg_fn_trip_status_sync();

CREATE TRIGGER trg_maintenance_status_sync
    AFTER INSERT OR UPDATE OF status ON maintenance_records
    FOR EACH ROW EXECUTE FUNCTION trg_fn_maintenance_status_sync();

CREATE TRIGGER trg_fuel_records_validate
    BEFORE INSERT OR UPDATE ON fuel_records
    FOR EACH ROW EXECUTE FUNCTION trg_fn_fuel_record_validate();
