CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

DROP SCHEMA IF EXISTS fleet CASCADE;
CREATE SCHEMA fleet;
SET search_path = fleet, public;

DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = fleet, public', current_database());
END $$;

CREATE TYPE vehicle_status AS ENUM ('available', 'on_trip', 'in_service', 'decommissioned');
CREATE TYPE trip_status AS ENUM ('planned', 'in_progress', 'completed', 'cancelled');
CREATE TYPE maintenance_status AS ENUM ('scheduled', 'in_progress', 'completed', 'cancelled');
CREATE TYPE policy_type AS ENUM ('osago', 'kasko');

-- users

CREATE TABLE roles (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(50) NOT NULL UNIQUE,
    description varchar(255)
);

CREATE TABLE users (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id smallint NOT NULL REFERENCES roles (id),
    login varchar(50) NOT NULL,
    password_hash varchar(255) NOT NULL,
    full_name varchar(150) NOT NULL,
    email varchar(150),
    created_at timestamptz NOT NULL DEFAULT now(),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_users_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL))
);

CREATE TABLE departments (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    address varchar(255),
    phone varchar(20),
    head_user_id integer REFERENCES users (id)
);

-- transport tables

CREATE TABLE license_categories (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code varchar(3) NOT NULL UNIQUE,
    description varchar(255) NOT NULL
);

CREATE TABLE vehicle_types (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(50) NOT NULL UNIQUE,
    required_category_id smallint NOT NULL REFERENCES license_categories (id)
);

CREATE TABLE manufacturers (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    country varchar(60)
);

CREATE TABLE fuel_types (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(30) NOT NULL UNIQUE,
    unit varchar(10) NOT NULL DEFAULT 'l'
);

CREATE TABLE vehicle_models (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    manufacturer_id integer NOT NULL REFERENCES manufacturers (id),
    vehicle_type_id smallint NOT NULL REFERENCES vehicle_types (id),
    fuel_type_id smallint NOT NULL REFERENCES fuel_types (id),
    name varchar(100) NOT NULL,
    tank_capacity numeric(6, 1) NOT NULL CHECK (tank_capacity > 0),
    seats smallint CHECK (seats > 0),
    payload_kg integer CHECK (payload_kg >= 0),
    CONSTRAINT uq_vehicle_models UNIQUE (manufacturer_id, name)
);

-- main entities

CREATE TABLE vehicles (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_id integer NOT NULL REFERENCES vehicle_models (id),
    department_id integer NOT NULL REFERENCES departments (id),
    plate_number varchar(10) NOT NULL,
    vin char(17) NOT NULL CHECK (vin ~ '^[A-HJ-NPR-Z0-9]{17}$'),
    manufacture_year smallint NOT NULL CHECK (manufacture_year BETWEEN 1980 AND 2100),
    color varchar(30),
    odometer_km integer NOT NULL DEFAULT 0 CHECK (odometer_km >= 0),
    status vehicle_status NOT NULL DEFAULT 'available',
    purchase_date date,
    purchase_price numeric(12, 2) CHECK (purchase_price >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_vehicles_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL))
);

CREATE TABLE drivers (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id integer NOT NULL REFERENCES departments (id),
    last_name varchar(60) NOT NULL,
    first_name varchar(60) NOT NULL,
    middle_name varchar(60),
    birth_date date NOT NULL,
    phone varchar(20) NOT NULL,
    email varchar(150),
    hire_date date NOT NULL DEFAULT current_date,
    license_number varchar(20) NOT NULL,
    license_expiry date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_drivers_age CHECK (birth_date <= hire_date - interval '18 years'),
    CONSTRAINT ck_drivers_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL))
);

CREATE TABLE driver_licenses (
    driver_id integer NOT NULL REFERENCES drivers (id) ON DELETE CASCADE,
    category_id smallint NOT NULL REFERENCES license_categories (id),
    obtained_date date NOT NULL,
    PRIMARY KEY (driver_id, category_id)
);

-- vehicle to driver assignments
CREATE TABLE vehicle_assignments (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    driver_id integer NOT NULL REFERENCES drivers (id),
    assigned_from date NOT NULL DEFAULT current_date,
    assigned_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    CONSTRAINT ck_assignments_period CHECK (assigned_to IS NULL OR assigned_to >= assigned_from),
    CONSTRAINT ex_assignments_vehicle_overlap EXCLUDE USING gist (
        vehicle_id WITH =,
        daterange(assigned_from, assigned_to, '[]') WITH &&
    )
);

CREATE TABLE routes (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL,
    start_point varchar(150) NOT NULL,
    end_point varchar(150) NOT NULL,
    distance_km numeric(8, 1) NOT NULL CHECK (distance_km > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_routes_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL))
);

CREATE TABLE trips (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    driver_id integer NOT NULL REFERENCES drivers (id),
    route_id integer REFERENCES routes (id),
    purpose varchar(255) NOT NULL,
    planned_start timestamptz NOT NULL,
    actual_start timestamptz,
    actual_end timestamptz,
    start_odometer integer,
    end_odometer integer,
    distance_km integer GENERATED ALWAYS AS (end_odometer - start_odometer) STORED,
    status trip_status NOT NULL DEFAULT 'planned',
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    CONSTRAINT ck_trips_odometer CHECK (end_odometer IS NULL OR end_odometer >= start_odometer),
    CONSTRAINT ck_trips_time CHECK (actual_end IS NULL OR actual_end >= actual_start),
    CONSTRAINT ck_trips_completed CHECK (
        status <> 'completed' OR (actual_start IS NOT NULL AND actual_end IS NOT NULL AND end_odometer IS NOT NULL)
    )
);

CREATE TABLE fuel_records (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    driver_id integer REFERENCES drivers (id),
    fuel_type_id smallint NOT NULL REFERENCES fuel_types (id),
    refuel_date timestamptz NOT NULL DEFAULT now(),
    liters numeric(7, 2) NOT NULL CHECK (liters > 0),
    price_per_liter numeric(8, 2) NOT NULL CHECK (price_per_liter > 0),
    total_cost numeric(12, 2) GENERATED ALWAYS AS (round(liters * price_per_liter, 2)) STORED,
    odometer_km integer CHECK (odometer_km >= 0),
    station varchar(150),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id)
);

-- vehicle service

CREATE TABLE service_centers (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL,
    address varchar(255) NOT NULL,
    phone varchar(20),
    created_at timestamptz NOT NULL DEFAULT now(),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_service_centers_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL))
);

CREATE TABLE maintenance_types (
    id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    interval_km integer CHECK (interval_km > 0),
    interval_months smallint CHECK (interval_months > 0)
);

CREATE TABLE maintenance_records (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    service_center_id integer NOT NULL REFERENCES service_centers (id),
    maintenance_type_id smallint NOT NULL REFERENCES maintenance_types (id),
    status maintenance_status NOT NULL DEFAULT 'scheduled',
    scheduled_date date NOT NULL,
    started_at timestamptz,
    completed_at timestamptz,
    odometer_km integer CHECK (odometer_km >= 0),
    cost numeric(12, 2) CHECK (cost >= 0),
    description text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    is_deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    deleted_by integer REFERENCES users (id),
    CONSTRAINT ck_maintenance_soft_delete CHECK (is_deleted = (deleted_at IS NOT NULL)),
    CONSTRAINT ck_maintenance_completed CHECK (status <> 'completed' OR completed_at IS NOT NULL)
);

-- insurance and fines

CREATE TABLE insurance_companies (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    phone varchar(20),
    website varchar(150)
);

CREATE TABLE insurance_policies (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    company_id integer NOT NULL REFERENCES insurance_companies (id),
    policy_number varchar(30) NOT NULL UNIQUE,
    policy_type policy_type NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    premium numeric(10, 2) NOT NULL CHECK (premium >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    CONSTRAINT ck_policies_period CHECK (end_date > start_date)
);

CREATE TABLE fines (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id integer NOT NULL REFERENCES vehicles (id),
    driver_id integer REFERENCES drivers (id),
    trip_id integer REFERENCES trips (id),
    violation_at timestamptz NOT NULL,
    description varchar(255) NOT NULL,
    amount numeric(10, 2) NOT NULL CHECK (amount > 0),
    is_paid boolean NOT NULL DEFAULT false,
    paid_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by integer REFERENCES users (id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by integer REFERENCES users (id),
    CONSTRAINT ck_fines_paid CHECK (is_paid = (paid_at IS NOT NULL))
);

-- audit
CREATE TABLE audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name varchar(63) NOT NULL,
    record_id bigint NOT NULL,
    operation varchar(12) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'SOFT_DELETE', 'RESTORE')),
    old_data jsonb,
    new_data jsonb,
    changed_by integer,
    changed_at timestamptz NOT NULL DEFAULT now()
);
