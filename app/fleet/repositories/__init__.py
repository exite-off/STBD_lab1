from fleet.repositories.drivers import DriverRepository
from fleet.repositories.fuel_records import FuelRecordRepository
from fleet.repositories.maintenance import MaintenanceRepository
from fleet.repositories.reports import ReportRepository
from fleet.repositories.trips import TripRepository
from fleet.repositories.vehicles import VehicleRepository

__all__ = [
    "DriverRepository",
    "FuelRecordRepository",
    "MaintenanceRepository",
    "ReportRepository",
    "TripRepository",
    "VehicleRepository",
]
