-- Demo of procedures, functions and triggers
SET search_path = fleet, public;
\set ON_ERROR_STOP off

BEGIN;

\echo '--- new trip: Shevchenko on Volvo (category CE) ---'
CALL sp_trip_plan(2, 6, 1, 1, 'Delivery to Lviv', now(), NULL) \gset trip_
SELECT id, status, plate_number, driver_name FROM v_trips ORDER BY id DESC LIMIT 1;

\echo '--- trip start: trigger sets vehicle status to on_trip ---'
CALL sp_trip_start(2, :trip_p_id);
SELECT plate_number, status, odometer_km FROM v_vehicles WHERE id = 6;

\echo '--- trip complete: trigger updates vehicle odometer ---'
CALL sp_trip_complete(2, :trip_p_id, 520545, 'No remarks');
SELECT plate_number, status, odometer_km, updated_by FROM v_vehicles WHERE id = 6;

\echo '--- refuel ---'
CALL sp_fuel_record_add(2, 6, 1, 180, 54.20, 'OKKO Lviv', now(), NULL);
SELECT plate_number, liters, total_cost, odometer_km FROM v_fuel_records ORDER BY id DESC LIMIT 1;

COMMIT;

\echo '--- error: driver with category B can not drive a bus (trigger) ---'
CALL sp_trip_plan(2, 7, 3, 5, 'Transfer', now(), NULL);

\echo '--- error: refuel bigger than tank capacity ---'
CALL sp_fuel_record_add(2, 1, 3, 90, 56.90, 'WOG', now(), NULL);

\echo '--- error: odometer can not decrease ---'
CALL sp_vehicle_update(1, 1, NULL, NULL, NULL, 100);

\echo '--- maintenance (mechanic): vehicle becomes in_service, then available ---'
CALL sp_maintenance_start(3, 5);
SELECT plate_number, status FROM v_vehicles WHERE id = 3;
CALL sp_maintenance_complete(3, 5, 12500, 'Maintenance done');
SELECT plate_number, status FROM v_vehicles WHERE id = 3;

\echo '--- soft delete and restore ---'
CALL sp_vehicle_delete(1, 2);
SELECT * FROM v_vehicles_deleted;
CALL sp_vehicle_restore(1, 2);
SELECT id, plate_number FROM v_vehicles WHERE id = 2;

\echo '--- vehicle change history ---'
SELECT changed_at, operation, changed_by, changes FROM fn_record_history('vehicles', 6) OFFSET 1;

\echo '--- costs and fuel consumption ---'
SELECT * FROM fn_vehicle_costs(6, current_date - 365, current_date);
SELECT fn_vehicle_fuel_consumption(6, current_date - 365, current_date) AS l_per_100km;

CALL sp_refresh_statistics();
SELECT * FROM mv_department_monthly_stats WHERE month = date_trunc('month', current_date)::date;
