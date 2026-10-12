SET search_path = fleet, public;
SET app.user_id = '1';

INSERT INTO roles (name, description) VALUES
    ('admin', 'System administrator'),
    ('dispatcher', 'Dispatcher: trips, drivers, vehicles'),
    ('mechanic', 'Mechanic: maintenance'),
    ('accountant', 'Accountant: costs, fines, insurance');

INSERT INTO users (role_id, login, password_hash, full_name, email) VALUES
    (1, 'admin', md5('admin'), 'Serhii Ivanenko', 'admin@fleet.ua'),
    (2, 'dispatcher', md5('dispatcher'), 'Olena Petrenko', 'dispatch@fleet.ua'),
    (3, 'mechanic', md5('mechanic'), 'Taras Sydorenko', 'service@fleet.ua'),
    (4, 'accountant', md5('accountant'), 'Mariia Honcharenko', 'finance@fleet.ua');

INSERT INTO departments (name, address, phone, head_user_id) VALUES
    ('Cargo transportation', 'Kyiv, 12 Promyslova St', '+380441112233', 2),
    ('Passenger transportation', 'Kyiv, 45 Peremohy Ave', '+380442223344', 2),
    ('Administrative transport', 'Kyiv, 1 Khreshchatyk St', '+380443334455', 1);

INSERT INTO license_categories (code, description) VALUES
    ('B', 'Cars up to 3500 kg'),
    ('C1', 'Trucks 3500-7500 kg'),
    ('C', 'Trucks over 3500 kg'),
    ('CE', 'Trucks with trailer over 750 kg'),
    ('D', 'Buses over 8 passengers');

INSERT INTO vehicle_types (name, required_category_id) VALUES
    ('Car', 1),
    ('Van', 1),
    ('Truck', 3),
    ('Tractor unit', 4),
    ('Bus', 5);

INSERT INTO manufacturers (name, country) VALUES
    ('Toyota', 'Japan'),
    ('Skoda', 'Czechia'),
    ('Renault', 'France'),
    ('Ford', 'USA'),
    ('MAN', 'Germany'),
    ('Volvo', 'Sweden'),
    ('Mercedes-Benz', 'Germany');

INSERT INTO fuel_types (name, unit) VALUES
    ('Petrol A-95', 'l'),
    ('Diesel', 'l'),
    ('LPG', 'l'),
    ('Electric', 'kWh');

INSERT INTO vehicle_models (manufacturer_id, vehicle_type_id, fuel_type_id, name, tank_capacity, seats, payload_kg) VALUES
    (1, 1, 1, 'Camry', 60, 5, 450),
    (2, 1, 1, 'Octavia', 50, 5, 500),
    (3, 2, 2, 'Master', 80, 3, 1500),
    (4, 2, 2, 'Transit', 80, 3, 1400),
    (5, 3, 2, 'TGL 12.250', 150, 2, 6500),
    (6, 4, 2, 'FH 460', 600, 2, 25000),
    (7, 5, 2, 'Tourismo', 480, 49, NULL),
    (1, 1, 4, 'bZ4X', 71.4, 5, 450);

INSERT INTO vehicles (model_id, department_id, plate_number, vin, manufacture_year, color, odometer_km, purchase_date, purchase_price) VALUES
    (1, 3, 'AA1001KA', 'JTNB11HK103000001', 2021, 'Black', 62000, '2021-03-15', 1250000),
    (2, 3, 'AA1002KA', 'TMBJJ7NE0L0000002', 2020, 'Grey', 88000, '2020-06-01', 780000),
    (3, 1, 'AA2001BH', 'VF1MA000060000003', 2019, 'White', 154000, '2019-02-20', 1100000),
    (4, 1, 'AA2002BH', 'WF0XXXTTGXK000004', 2022, 'White', 41000, '2022-04-10', 1350000),
    (5, 1, 'AA3001CE', 'WMAN08ZZ1KY000005', 2018, 'Blue', 310000, '2018-09-05', 2400000),
    (6, 1, 'AA3002CE', 'YV2RT40A0LB000006', 2020, 'Red', 520000, '2020-01-25', 4800000),
    (7, 2, 'AA4001MO', 'WEB63231302000007', 2017, 'White', 690000, '2017-05-30', 7200000),
    (8, 3, 'AA5001EE', 'JTMAB3FV0PD000008', 2023, 'Blue', 18000, '2023-08-12', 1900000),
    (2, 3, 'AA0999XX', 'TMBJJ7NE0F0000009', 2015, 'Green', 260000, '2015-03-01', 520000);

INSERT INTO drivers (department_id, last_name, first_name, middle_name, birth_date, phone, email, hire_date, license_number, license_expiry) VALUES
    (1, 'Shevchenko', 'Andrii', 'Petrovych', '1980-04-12', '+380501110001', 'shevchenko@fleet.ua', '2015-02-01', 'AXA100001', '2030-04-12'),
    (1, 'Kovalenko', 'Oleh', 'Ivanovych', '1985-09-23', '+380501110002', 'kovalenko@fleet.ua', '2017-06-15', 'AXA100002', '2029-09-23'),
    (3, 'Bondarenko', 'Iryna', 'Vasylivna', '1990-01-30', '+380501110003', 'bondarenko@fleet.ua', '2019-03-01', 'AXA100003', '2031-01-30'),
    (2, 'Tkachenko', 'Vasyl', 'Mykolaiovych', '1978-11-05', '+380501110004', 'tkachenko@fleet.ua', '2012-08-20', 'AXA100004', '2028-11-05'),
    (1, 'Kravchenko', 'Mykola', 'Olehovych', '1992-07-17', '+380501110005', 'kravchenko@fleet.ua', '2020-10-01', 'AXA100005', '2032-07-17'),
    (3, 'Melnyk', 'Svitlana', 'Andriivna', '1988-03-08', '+380501110006', 'melnyk@fleet.ua', '2018-01-10', 'AXA100006', current_date + 20),
    (1, 'Oliinyk', 'Petro', 'Serhiiovych', '1975-12-01', '+380501110007', NULL, '2010-05-05', 'AXA100007', '2027-12-01');

INSERT INTO driver_licenses (driver_id, category_id, obtained_date) VALUES
    (1, 1, '1998-05-01'), (1, 3, '2002-06-01'), (1, 4, '2005-07-01'),
    (2, 1, '2003-10-01'), (2, 3, '2008-03-01'),
    (3, 1, '2008-02-15'),
    (4, 1, '1996-12-01'), (4, 5, '2004-04-01'),
    (5, 1, '2010-08-01'),
    (6, 1, '2006-04-01'),
    (7, 1, '1994-01-10'), (7, 3, '1999-02-10');

INSERT INTO vehicle_assignments (vehicle_id, driver_id, assigned_from, assigned_to, created_by) VALUES
    (6, 1, '2023-01-01', NULL, 2),
    (5, 2, '2023-01-01', NULL, 2),
    (1, 3, '2023-01-01', NULL, 2),
    (7, 4, '2023-01-01', NULL, 2),
    (3, 5, '2023-01-01', '2024-12-31', 2),
    (4, 5, '2025-01-01', NULL, 2),
    (3, 7, '2025-01-01', NULL, 2),
    (8, 6, '2024-01-01', NULL, 2),
    (2, 6, '2022-01-01', '2023-12-31', 2);

INSERT INTO routes (name, start_point, end_point, distance_km) VALUES
    ('Kyiv - Lviv', 'Kyiv, warehouse 1', 'Lviv, 200 Horodotska St', 540),
    ('Kyiv - Odesa', 'Kyiv, warehouse 1', 'Odesa, sea port', 475),
    ('Kyiv - Zhytomyr', 'Kyiv, warehouse 2', 'Zhytomyr, 77 Kyivska St', 140),
    ('City route', 'Kyiv, office', 'Kyiv, office', 60),
    ('Kyiv - Boryspil (airport)', 'Kyiv, 45 Peremohy Ave', 'Boryspil Airport', 38);

INSERT INTO service_centers (name, address, phone) VALUES
    ('AutoService Plus', 'Kyiv, 5 Avtozavodska St', '+380445550001'),
    ('TruckService', 'Kyiv, 20 Ring Road', '+380445550002'),
    ('ElectroCar Service', 'Kyiv, 100 Antonovycha St', '+380445550003');

INSERT INTO maintenance_types (name, interval_km, interval_months) VALUES
    ('Oil and filters change', 15000, 12),
    ('Brake pads replacement', 40000, NULL),
    ('Seasonal tire change', NULL, 6),
    ('Scheduled service', 30000, 24),
    ('Diagnostics', NULL, 12);

INSERT INTO insurance_companies (name, phone, website) VALUES
    ('Oberih Insurance', '+380800500100', 'oberig.example.ua'),
    ('Ukrainian Insurance Group', '+380800500200', 'usg.example.ua'),
    ('Garant-Auto', '+380800500300', 'garant.example.ua');

-- historical trips and refuels: odometer is counted back from the current value
DO $$
DECLARE
    a record;
    k integer;
    v_dist integer;
    v_end integer;
    v_start_time timestamptz;
    v_route integer;
    v_rate numeric;
    v_tank numeric;
BEGIN
    FOR a IN
        SELECT va.vehicle_id, va.driver_id, v.odometer_km, m.tank_capacity, m.vehicle_type_id
        FROM vehicle_assignments va
        JOIN vehicles v ON v.id = va.vehicle_id
        JOIN vehicle_models m ON m.id = v.model_id
        WHERE va.assigned_to IS NULL AND v.id <> 9
    LOOP
        v_end := a.odometer_km;
        v_tank := a.tank_capacity;
        v_rate := CASE a.vehicle_type_id WHEN 1 THEN 8 WHEN 2 THEN 11 WHEN 3 THEN 22 WHEN 4 THEN 32 ELSE 28 END;
        FOR k IN 1..8 LOOP
            v_route := 1 + (a.vehicle_id + k) % 5;
            v_dist := 40 + (a.vehicle_id * 37 + k * 53) % 420;
            v_start_time := date_trunc('day', now()) - (k * 9 + a.vehicle_id) * interval '1 day' + interval '8 hours';

            INSERT INTO trips (vehicle_id, driver_id, route_id, purpose, planned_start, actual_start, actual_end,
                               start_odometer, end_odometer, status)
            VALUES (a.vehicle_id, a.driver_id, v_route, 'Scheduled trip', v_start_time, v_start_time + interval '10 minutes',
                    v_start_time + (v_dist / 60.0) * interval '1 hour' + interval '10 minutes',
                    v_end - v_dist, v_end, 'completed');

            INSERT INTO fuel_records (vehicle_id, driver_id, refuel_date, liters, price_per_liter, odometer_km, station)
            VALUES (a.vehicle_id, a.driver_id, v_start_time + interval '12 hours',
                    least(round(v_dist * v_rate / 100.0 * (0.9 + (k % 3) * 0.1), 2), v_tank),
                    CASE a.vehicle_type_id WHEN 1 THEN 56.90 ELSE 54.50 END - (k % 4),
                    v_end, CASE k % 3 WHEN 0 THEN 'WOG' WHEN 1 THEN 'OKKO' ELSE 'SOCAR' END);

            v_end := v_end - v_dist;
        END LOOP;
    END LOOP;
END $$;

-- electric car is charged, not refueled with petrol
UPDATE fuel_records SET price_per_liter = 7.50, station = 'TOKA charging station' WHERE vehicle_id = 8;

INSERT INTO maintenance_records (vehicle_id, service_center_id, maintenance_type_id, status, scheduled_date, started_at, completed_at, odometer_km, cost, description) VALUES
    (5, 2, 1, 'completed', current_date - 60, now() - interval '60 days', now() - interval '59 days', 305000, 8500, 'Oil and filters change'),
    (6, 2, 4, 'completed', current_date - 45, now() - interval '45 days', now() - interval '43 days', 515000, 42000, 'Scheduled service #3'),
    (1, 1, 3, 'completed', current_date - 30, now() - interval '30 days', now() - interval '30 days', 61500, 1600, 'Seasonal tire change'),
    (7, 2, 2, 'completed', current_date - 20, now() - interval '20 days', now() - interval '19 days', 688000, 15800, 'Front brake pads'),
    (3, 1, 4, 'scheduled', current_date + 7, NULL, NULL, NULL, NULL, 'Scheduled service'),
    (8, 3, 5, 'scheduled', current_date + 14, NULL, NULL, NULL, NULL, 'Battery diagnostics');

INSERT INTO insurance_policies (vehicle_id, company_id, policy_number, policy_type, start_date, end_date, premium) VALUES
    (1, 1, 'OSG-2026-0001', 'osago', current_date - 200, current_date + 165, 2400),
    (1, 1, 'KSK-2026-0001', 'kasko', current_date - 200, current_date + 165, 38000),
    (2, 2, 'OSG-2025-0002', 'osago', current_date - 350, current_date + 15, 2200),
    (3, 2, 'OSG-2026-0003', 'osago', current_date - 100, current_date + 265, 3100),
    (4, 3, 'OSG-2026-0004', 'osago', current_date - 30, current_date + 335, 3100),
    (5, 3, 'OSG-2025-0005', 'osago', current_date - 370, current_date - 5, 5200),
    (6, 1, 'OSG-2026-0006', 'osago', current_date - 90, current_date + 275, 7400),
    (6, 1, 'KSK-2026-0006', 'kasko', current_date - 90, current_date + 275, 96000),
    (7, 2, 'OSG-2026-0007', 'osago', current_date - 150, current_date + 215, 6800),
    (8, 3, 'OSG-2026-0008', 'osago', current_date - 10, current_date + 355, 2400);

INSERT INTO fines (vehicle_id, driver_id, violation_at, description, amount, is_paid, paid_at) VALUES
    (6, 1, now() - interval '40 days', 'Speeding by 20-40 km/h', 340, true, now() - interval '35 days'),
    (5, 2, now() - interval '25 days', 'Stopping rules violation', 680, false, NULL),
    (1, 3, now() - interval '12 days', 'Speeding by 20-40 km/h', 340, false, NULL);

-- soft delete demo: fired driver and decommissioned vehicle
DELETE FROM drivers WHERE id = 7;
UPDATE vehicle_assignments SET assigned_to = current_date WHERE vehicle_id = 3 AND driver_id = 7;
DELETE FROM vehicles WHERE id = 9;

RESET app.user_id;

REFRESH MATERIALIZED VIEW mv_department_monthly_stats;
