from datetime import date

from fleet.models import DeletedRecord, NewVehicle, Vehicle
from fleet.repositories.base import RepositoryBase


class VehicleRepository(RepositoryBase):
    def get_all(self) -> list[Vehicle]:
        return self._query(Vehicle, "SELECT * FROM v_vehicles ORDER BY plate_number")

    def get_by_id(self, vehicle_id: int) -> Vehicle | None:
        return self._query_one(Vehicle, "SELECT * FROM v_vehicles WHERE id = %s", vehicle_id)

    def get_deleted(self) -> list[DeletedRecord]:
        rows = self._rows("SELECT * FROM v_vehicles_deleted ORDER BY deleted_at DESC")
        return [DeletedRecord(id=r["id"], title=f"{r['plate_number']} ({r['model']})",
                              deleted_at=r["deleted_at"], deleted_by=r["deleted_by"]) for r in rows]

    def get_available_for_driver(self, driver_id: int) -> list[Vehicle]:
        return self._query(Vehicle, "SELECT * FROM fn_available_vehicles(%s)", driver_id)

    def add(self, vehicle: NewVehicle) -> int:
        v = vehicle
        return self._call_returning_id("sp_vehicle_create", v.model_id, v.department_id, v.plate_number, v.vin,
                                       v.manufacture_year, v.color, v.odometer_km, v.purchase_date,
                                       v.purchase_price)

    def update(self, vehicle_id: int, *, department_id: int | None = None, plate_number: str | None = None,
               color: str | None = None, odometer_km: int | None = None) -> None:
        self._call("sp_vehicle_update", vehicle_id, department_id, plate_number, color, odometer_km)

    def assign_driver(self, vehicle_id: int, driver_id: int, date_from: date) -> None:
        self._call("sp_vehicle_assign", vehicle_id, driver_id, date_from)

    def delete(self, vehicle_id: int) -> None:
        self._call("sp_vehicle_delete", vehicle_id)

    def restore(self, vehicle_id: int) -> None:
        self._call("sp_vehicle_restore", vehicle_id)
