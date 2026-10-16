from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any

# field names match column names of the views, so rows map directly


@dataclass(frozen=True, slots=True, kw_only=True)
class Vehicle:
    id: int
    plate_number: str
    vin: str
    model_id: int
    manufacturer: str
    model: str
    vehicle_type: str
    required_category: str
    fuel_type: str
    manufacture_year: int
    color: str | None
    odometer_km: int
    status: str
    department_id: int
    department: str
    updated_at: datetime
    updated_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class NewVehicle:
    model_id: int
    department_id: int
    plate_number: str
    vin: str
    manufacture_year: int
    color: str | None
    odometer_km: int
    purchase_date: date | None
    purchase_price: Decimal | None


@dataclass(frozen=True, slots=True, kw_only=True)
class Driver:
    id: int
    full_name: str
    phone: str
    email: str | None
    department_id: int
    department: str
    license_number: str
    license_expiry: date
    license_valid: bool
    categories: str
    assigned_vehicle: str | None
    updated_at: datetime
    updated_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class NewDriver:
    department_id: int
    last_name: str
    first_name: str
    middle_name: str | None
    birth_date: date
    phone: str
    email: str | None
    license_number: str
    license_expiry: date


# recycle bin record (v_vehicles_deleted, v_drivers_deleted)
@dataclass(frozen=True, slots=True, kw_only=True)
class DeletedRecord:
    id: int
    title: str
    deleted_at: datetime
    deleted_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class Trip:
    id: int
    status: str
    vehicle_id: int
    plate_number: str
    driver_id: int
    driver_name: str
    route_name: str | None
    purpose: str
    planned_start: datetime
    actual_start: datetime | None
    actual_end: datetime | None
    start_odometer: int | None
    end_odometer: int | None
    distance_km: int | None
    updated_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class FuelRecord:
    id: int
    vehicle_id: int
    plate_number: str
    driver_name: str | None
    fuel_type: str
    refuel_date: datetime
    liters: Decimal
    price_per_liter: Decimal
    total_cost: Decimal
    odometer_km: int | None
    station: str | None
    created_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class MaintenanceRecord:
    id: int
    vehicle_id: int
    plate_number: str
    maintenance_type: str
    service_center: str
    status: str
    scheduled_date: date
    started_at: datetime | None
    completed_at: datetime | None
    cost: Decimal | None
    description: str | None
    updated_by: str | None


@dataclass(frozen=True, slots=True, kw_only=True)
class ExpiringDocument:
    document_type: str
    owner: str
    document_number: str
    expires_on: date
    days_left: int


@dataclass(frozen=True, slots=True, kw_only=True)
class VehicleStats:
    vehicle_id: int
    plate_number: str
    odometer_km: int
    trips_completed: int
    trips_km: int
    fuel_liters: Decimal
    fuel_cost: Decimal
    maintenance_cost: Decimal
    unpaid_fines: Decimal
    avg_consumption: Decimal | None


@dataclass(frozen=True, slots=True, kw_only=True)
class VehicleCosts:
    fuel_cost: Decimal
    maintenance_cost: Decimal
    fines_amount: Decimal
    insurance_cost: Decimal
    total_cost: Decimal


@dataclass(frozen=True, slots=True, kw_only=True)
class HistoryEntry:
    changed_at: datetime
    operation: str
    changed_by: str
    changes: dict[str, Any]
