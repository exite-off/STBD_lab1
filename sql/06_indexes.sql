SET search_path = fleet, public;

-- B-tree unique partial with expression: plate and VIN are unique only among not deleted rows
CREATE UNIQUE INDEX ux_vehicles_plate_active ON vehicles (upper(plate_number)) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_vehicles_vin_active ON vehicles (vin) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_drivers_license_active ON drivers (license_number) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_users_login_active ON users (lower(login)) WHERE NOT is_deleted;

-- B-tree on foreign keys
CREATE INDEX ix_vehicles_model ON vehicles (model_id);
CREATE INDEX ix_vehicles_department_status ON vehicles (department_id, status) WHERE NOT is_deleted;
CREATE INDEX ix_drivers_department ON drivers (department_id) WHERE NOT is_deleted;
CREATE INDEX ix_assignments_driver ON vehicle_assignments (driver_id);
CREATE INDEX ix_policies_vehicle_end ON insurance_policies (vehicle_id, policy_type, end_date DESC);
CREATE INDEX ix_fines_vehicle ON fines (vehicle_id, violation_at DESC);
CREATE INDEX ix_fines_unpaid ON fines (vehicle_id) WHERE NOT is_paid;

-- B-tree composite for trips
CREATE INDEX ix_trips_vehicle_start ON trips (vehicle_id, actual_start DESC);
CREATE INDEX ix_trips_driver_planned ON trips (driver_id, planned_start DESC);
-- partial: active trips (used by trg_fn_trip_validate)
CREATE INDEX ix_trips_in_progress ON trips (vehicle_id, driver_id) WHERE status = 'in_progress';

-- covering B-tree (INCLUDE) for fuel reports
CREATE INDEX ix_fuel_vehicle_date ON fuel_records (vehicle_id, refuel_date) INCLUDE (liters, total_cost);

CREATE INDEX ix_maintenance_vehicle_active ON maintenance_records (vehicle_id, scheduled_date)
    WHERE NOT is_deleted AND status IN ('scheduled', 'in_progress');

-- BRIN for time columns that grow with physical row order
CREATE INDEX ix_trips_planned_brin ON trips USING brin (planned_start);
CREATE INDEX ix_audit_log_changed_brin ON audit_log USING brin (changed_at);

-- Hash: equality lookups only
CREATE INDEX ix_drivers_phone_hash ON drivers USING hash (phone);
CREATE INDEX ix_vehicles_vin_hash ON vehicles USING hash (vin);

-- GIN: search inside audit jsonb and fuzzy driver search by last name
CREATE INDEX ix_audit_log_new_data_gin ON audit_log USING gin (new_data jsonb_path_ops);
CREATE INDEX ix_drivers_last_name_trgm ON drivers USING gin (last_name gin_trgm_ops);

CREATE INDEX ix_audit_log_record ON audit_log (table_name, record_id, changed_at);
