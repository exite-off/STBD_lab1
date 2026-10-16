from datetime import date

from fleet.models import DeletedRecord, Driver, NewDriver
from fleet.repositories.base import RepositoryBase


class DriverRepository(RepositoryBase):
    def get_all(self) -> list[Driver]:
        return self._query(Driver, "SELECT * FROM v_drivers ORDER BY full_name")

    def get_by_id(self, driver_id: int) -> Driver | None:
        return self._query_one(Driver, "SELECT * FROM v_drivers WHERE id = %s", driver_id)

    def get_by_license(self, license_number: str) -> Driver | None:
        return self._query_one(Driver, "SELECT * FROM v_drivers WHERE license_number = upper(%s)", license_number)

    # fuzzy search, uses GIN trigram index
    def search_by_last_name(self, last_name: str) -> list[Driver]:
        return self._query(Driver, "SELECT * FROM v_drivers WHERE last_name %% %s "
                                   "ORDER BY similarity(last_name, %s) DESC", last_name, last_name)

    def get_deleted(self) -> list[DeletedRecord]:
        rows = self._rows("SELECT * FROM v_drivers_deleted ORDER BY deleted_at DESC")
        return [DeletedRecord(id=r["id"], title=r["full_name"], deleted_at=r["deleted_at"],
                              deleted_by=r["deleted_by"]) for r in rows]

    def add(self, driver: NewDriver) -> int:
        d = driver
        return self._call_returning_id("sp_driver_create", d.department_id, d.last_name, d.first_name,
                                       d.middle_name, d.birth_date, d.phone, d.email, d.license_number,
                                       d.license_expiry)

    def update(self, driver_id: int, *, department_id: int | None = None, phone: str | None = None,
               email: str | None = None, license_number: str | None = None,
               license_expiry: date | None = None) -> None:
        self._call("sp_driver_update", driver_id, department_id, phone, email, license_number, license_expiry)

    def add_license_category(self, driver_id: int, category_code: str, obtained: date) -> None:
        self._call("sp_driver_add_license", driver_id, category_code, obtained)

    def delete(self, driver_id: int) -> None:
        self._call("sp_driver_delete", driver_id)

    def restore(self, driver_id: int) -> None:
        self._call("sp_driver_restore", driver_id)
