from datetime import UTC, datetime
from decimal import Decimal

from fleet.models import FuelRecord
from fleet.repositories.base import RepositoryBase


class FuelRecordRepository(RepositoryBase):
    def get_by_vehicle(self, vehicle_id: int, limit: int = 10) -> list[FuelRecord]:
        return self._query(FuelRecord, "SELECT * FROM v_fuel_records WHERE vehicle_id = %s "
                                       "ORDER BY refuel_date DESC LIMIT %s", vehicle_id, limit)

    def add(self, vehicle_id: int, driver_id: int | None, liters: Decimal, price_per_liter: Decimal,
            station: str | None, refuel_date: datetime | None = None) -> int:
        return self._call_returning_id("sp_fuel_record_add", vehicle_id, driver_id, liters, price_per_liter,
                                       station, refuel_date or datetime.now(UTC))
