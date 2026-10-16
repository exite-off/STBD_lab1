from datetime import date, datetime

from fleet.models import Trip
from fleet.repositories.base import RepositoryBase


class TripRepository(RepositoryBase):
    def get_by_id(self, trip_id: int) -> Trip | None:
        return self._query_one(Trip, "SELECT * FROM v_trips WHERE id = %s", trip_id)

    def get_active(self) -> list[Trip]:
        return self._query(Trip, "SELECT * FROM v_trips WHERE status IN ('planned', 'in_progress') "
                                 "ORDER BY planned_start")

    def get_by_driver(self, driver_id: int, date_from: date, date_to: date) -> list[Trip]:
        return self._query(Trip, "SELECT * FROM fn_driver_trips(%s, %s, %s)", driver_id, date_from, date_to)

    def plan(self, vehicle_id: int, driver_id: int, route_id: int | None, purpose: str,
             planned_start: datetime) -> int:
        return self._call_returning_id("sp_trip_plan", vehicle_id, driver_id, route_id, purpose, planned_start)

    def start(self, trip_id: int) -> None:
        self._call("sp_trip_start", trip_id)

    def complete(self, trip_id: int, end_odometer: int, notes: str | None = None) -> None:
        self._call("sp_trip_complete", trip_id, end_odometer, notes)

    def cancel(self, trip_id: int, reason: str) -> None:
        self._call("sp_trip_cancel", trip_id, reason)
