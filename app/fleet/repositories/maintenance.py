from datetime import date
from decimal import Decimal

from fleet.models import MaintenanceRecord
from fleet.repositories.base import RepositoryBase


class MaintenanceRepository(RepositoryBase):
    def get_by_id(self, record_id: int) -> MaintenanceRecord | None:
        return self._query_one(MaintenanceRecord, "SELECT * FROM v_maintenance WHERE id = %s", record_id)

    def get_by_vehicle(self, vehicle_id: int) -> list[MaintenanceRecord]:
        return self._query(MaintenanceRecord, "SELECT * FROM v_maintenance WHERE vehicle_id = %s "
                                              "ORDER BY scheduled_date DESC", vehicle_id)

    def schedule(self, vehicle_id: int, service_center_id: int, maintenance_type_id: int, scheduled: date,
                 description: str | None) -> int:
        return self._call_returning_id("sp_maintenance_schedule", vehicle_id, service_center_id,
                                       maintenance_type_id, scheduled, description)

    def start(self, record_id: int) -> None:
        self._call("sp_maintenance_start", record_id)

    def complete(self, record_id: int, cost: Decimal, description: str | None = None) -> None:
        self._call("sp_maintenance_complete", record_id, cost, description)

    def delete(self, record_id: int) -> None:
        self._call("sp_maintenance_delete", record_id)
