from datetime import date
from decimal import Decimal

from fleet.models import ExpiringDocument, HistoryEntry, VehicleCosts, VehicleStats
from fleet.repositories.base import RepositoryBase


class ReportRepository(RepositoryBase):
    def get_expiring_documents(self) -> list[ExpiringDocument]:
        return self._query(ExpiringDocument, "SELECT * FROM v_expiring_documents ORDER BY days_left")

    def get_vehicle_stats(self) -> list[VehicleStats]:
        return self._query(VehicleStats, "SELECT * FROM v_vehicle_stats ORDER BY plate_number")

    def get_vehicle_costs(self, vehicle_id: int, date_from: date, date_to: date) -> VehicleCosts:
        return self._query(VehicleCosts, "SELECT * FROM fn_vehicle_costs(%s, %s, %s)",
                           vehicle_id, date_from, date_to)[0]

    def get_fuel_consumption(self, vehicle_id: int, date_from: date, date_to: date) -> Decimal | None:
        return self._scalar("SELECT fn_vehicle_fuel_consumption(%s, %s, %s)", vehicle_id, date_from, date_to)

    def get_history(self, table: str, record_id: int) -> list[HistoryEntry]:
        return self._query(HistoryEntry, "SELECT * FROM fn_record_history(%s, %s)", table, record_id)

    def refresh_statistics(self) -> None:
        self._call_without_user("sp_refresh_statistics")
