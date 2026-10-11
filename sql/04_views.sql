SET search_path = fleet, public;

-- active vehicles with catalog data
CREATE OR REPLACE VIEW v_vehicles AS
SELECT v.id,
       v.plate_number,
       v.vin,
       v.model_id,
       mf.name AS manufacturer,
       m.name AS model,
       vt.name AS vehicle_type,
       lc.code AS required_category,
       ft.name AS fuel_type,
       m.tank_capacity,
       v.manufacture_year,
       v.color,
       v.odometer_km,
       v.status::text AS status,
       v.department_id,
       d.name AS department,
       v.purchase_date,
       v.purchase_price,
       v.created_at,
       cu.full_name AS created_by,
       v.updated_at,
       uu.full_name AS updated_by
FROM vehicles v
JOIN vehicle_models m ON m.id = v.model_id
JOIN manufacturers mf ON mf.id = m.manufacturer_id
JOIN vehicle_types vt ON vt.id = m.vehicle_type_id
JOIN license_categories lc ON lc.id = vt.required_category_id
JOIN fuel_types ft ON ft.id = m.fuel_type_id
JOIN departments d ON d.id = v.department_id
LEFT JOIN users cu ON cu.id = v.created_by
LEFT JOIN users uu ON uu.id = v.updated_by
WHERE NOT v.is_deleted;

-- recycle bin of deleted vehicles
CREATE OR REPLACE VIEW v_vehicles_deleted AS
SELECT v.id,
       v.plate_number,
       v.vin,
       mf.name || ' ' || m.name AS model,
       v.deleted_at,
       du.full_name AS deleted_by
FROM vehicles v
JOIN vehicle_models m ON m.id = v.model_id
JOIN manufacturers mf ON mf.id = m.manufacturer_id
LEFT JOIN users du ON du.id = v.deleted_by
WHERE v.is_deleted;

-- active drivers with categories and currently assigned vehicle
CREATE OR REPLACE VIEW v_drivers AS
SELECT d.id,
       d.last_name,
       d.first_name,
       d.middle_name,
       concat_ws(' ', d.last_name, d.first_name, d.middle_name) AS full_name,
       d.birth_date,
       d.phone,
       d.email,
       d.hire_date,
       d.department_id,
       dep.name AS department,
       d.license_number,
       d.license_expiry,
       d.license_expiry >= current_date AS license_valid,
       coalesce(cat.categories, '') AS categories,
       cur.plate_number AS assigned_vehicle,
       d.updated_at,
       uu.full_name AS updated_by
FROM drivers d
JOIN departments dep ON dep.id = d.department_id
LEFT JOIN users uu ON uu.id = d.updated_by
LEFT JOIN LATERAL (
    SELECT string_agg(lc.code, ', ' ORDER BY lc.code) AS categories
    FROM driver_licenses dl
    JOIN license_categories lc ON lc.id = dl.category_id
    WHERE dl.driver_id = d.id
) cat ON true
LEFT JOIN LATERAL (
    SELECT v.plate_number
    FROM vehicle_assignments a
    JOIN vehicles v ON v.id = a.vehicle_id
    WHERE a.driver_id = d.id
      AND current_date BETWEEN a.assigned_from AND coalesce(a.assigned_to, 'infinity')
    ORDER BY a.assigned_from DESC
    LIMIT 1
) cur ON true
WHERE NOT d.is_deleted;

CREATE OR REPLACE VIEW v_drivers_deleted AS
SELECT d.id,
       concat_ws(' ', d.last_name, d.first_name, d.middle_name) AS full_name,
       d.license_number,
       d.deleted_at,
       du.full_name AS deleted_by
FROM drivers d
LEFT JOIN users du ON du.id = d.deleted_by
WHERE d.is_deleted;

-- trips with details
CREATE OR REPLACE VIEW v_trips AS
SELECT t.id,
       t.status::text AS status,
       t.vehicle_id,
       v.plate_number,
       t.driver_id,
       concat_ws(' ', d.last_name, d.first_name) AS driver_name,
       t.route_id,
       r.name AS route_name,
       t.purpose,
       t.planned_start,
       t.actual_start,
       t.actual_end,
       t.start_odometer,
       t.end_odometer,
       t.distance_km,
       t.actual_end - t.actual_start AS duration,
       t.notes,
       t.updated_at,
       uu.full_name AS updated_by
FROM trips t
JOIN vehicles v ON v.id = t.vehicle_id
JOIN drivers d ON d.id = t.driver_id
LEFT JOIN routes r ON r.id = t.route_id
LEFT JOIN users uu ON uu.id = t.updated_by;

CREATE OR REPLACE VIEW v_fuel_records AS
SELECT f.id,
       f.vehicle_id,
       v.plate_number,
       f.driver_id,
       concat_ws(' ', d.last_name, d.first_name) AS driver_name,
       ft.name AS fuel_type,
       f.refuel_date,
       f.liters,
       f.price_per_liter,
       f.total_cost,
       f.odometer_km,
       f.station,
       cu.full_name AS created_by
FROM fuel_records f
JOIN vehicles v ON v.id = f.vehicle_id
JOIN fuel_types ft ON ft.id = f.fuel_type_id
LEFT JOIN drivers d ON d.id = f.driver_id
LEFT JOIN users cu ON cu.id = f.created_by;

-- maintenance without deleted records
CREATE OR REPLACE VIEW v_maintenance AS
SELECT mr.id,
       mr.vehicle_id,
       v.plate_number,
       mt.name AS maintenance_type,
       sc.name AS service_center,
       mr.status::text AS status,
       mr.scheduled_date,
       mr.started_at,
       mr.completed_at,
       mr.odometer_km,
       mr.cost,
       mr.description,
       mr.updated_at,
       uu.full_name AS updated_by
FROM maintenance_records mr
JOIN vehicles v ON v.id = mr.vehicle_id
JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
JOIN service_centers sc ON sc.id = mr.service_center_id
LEFT JOIN users uu ON uu.id = mr.updated_by
WHERE NOT mr.is_deleted;

-- documents expiring within 30 days or already expired
CREATE OR REPLACE VIEW v_expiring_documents AS
SELECT 'Driver license'::varchar AS document_type,
       concat_ws(' ', d.last_name, d.first_name) AS owner,
       d.license_number AS document_number,
       d.license_expiry AS expires_on,
       d.license_expiry - current_date AS days_left
FROM drivers d
WHERE NOT d.is_deleted AND d.license_expiry <= current_date + 30
UNION ALL
SELECT 'Policy ' || upper(p.policy_type::text),
       v.plate_number,
       p.policy_number,
       p.end_date,
       p.end_date - current_date
FROM insurance_policies p
JOIN vehicles v ON v.id = p.vehicle_id
WHERE NOT v.is_deleted
  AND p.end_date <= current_date + 30
  -- no newer policy of the same type
  AND NOT EXISTS (
      SELECT 1 FROM insurance_policies p2
      WHERE p2.vehicle_id = p.vehicle_id AND p2.policy_type = p.policy_type AND p2.end_date > p.end_date
  );

-- summary statistics per vehicle
CREATE OR REPLACE VIEW v_vehicle_stats AS
SELECT v.id AS vehicle_id,
       v.plate_number,
       v.odometer_km,
       coalesce(t.trips_count, 0) AS trips_completed,
       coalesce(t.km, 0) AS trips_km,
       coalesce(f.liters, 0) AS fuel_liters,
       coalesce(f.cost, 0) AS fuel_cost,
       coalesce(mt.cost, 0) AS maintenance_cost,
       coalesce(fn.unpaid, 0) AS unpaid_fines,
       CASE WHEN coalesce(t.km, 0) > 0 THEN round(f.liters / t.km * 100, 2) END AS avg_consumption
FROM vehicles v
LEFT JOIN (
    SELECT vehicle_id, count(*) AS trips_count, sum(distance_km) AS km
    FROM trips WHERE status = 'completed' GROUP BY vehicle_id
) t ON t.vehicle_id = v.id
LEFT JOIN (
    SELECT vehicle_id, sum(liters) AS liters, sum(total_cost) AS cost
    FROM fuel_records GROUP BY vehicle_id
) f ON f.vehicle_id = v.id
LEFT JOIN (
    SELECT vehicle_id, sum(cost) AS cost
    FROM maintenance_records WHERE status = 'completed' AND NOT is_deleted GROUP BY vehicle_id
) mt ON mt.vehicle_id = v.id
LEFT JOIN (
    SELECT vehicle_id, sum(amount) AS unpaid
    FROM fines WHERE NOT is_paid GROUP BY vehicle_id
) fn ON fn.vehicle_id = v.id
WHERE NOT v.is_deleted;

-- materialized view: monthly department statistics
CREATE MATERIALIZED VIEW mv_department_monthly_stats AS
WITH months AS (
    SELECT v.department_id, date_trunc('month', t.actual_end)::date AS month,
           count(*) AS trips, sum(t.distance_km) AS km, 0::numeric AS fuel_cost, 0::numeric AS maintenance_cost
    FROM trips t JOIN vehicles v ON v.id = t.vehicle_id
    WHERE t.status = 'completed'
    GROUP BY 1, 2
    UNION ALL
    SELECT v.department_id, date_trunc('month', f.refuel_date)::date, 0, 0, sum(f.total_cost), 0
    FROM fuel_records f JOIN vehicles v ON v.id = f.vehicle_id
    GROUP BY 1, 2
    UNION ALL
    SELECT v.department_id, date_trunc('month', m.completed_at)::date, 0, 0, 0, sum(m.cost)
    FROM maintenance_records m JOIN vehicles v ON v.id = m.vehicle_id
    WHERE m.status = 'completed' AND NOT m.is_deleted
    GROUP BY 1, 2
)
SELECT d.id AS department_id,
       d.name AS department,
       mo.month,
       sum(mo.trips)::integer AS trips,
       sum(mo.km)::integer AS km,
       sum(mo.fuel_cost) AS fuel_cost,
       sum(mo.maintenance_cost) AS maintenance_cost
FROM months mo
JOIN departments d ON d.id = mo.department_id
GROUP BY d.id, d.name, mo.month;

CREATE UNIQUE INDEX ux_mv_department_monthly_stats ON mv_department_monthly_stats (department_id, month);
