from types import TracebackType
from typing import Self

import psycopg

from fleet.repositories import (DriverRepository, FuelRecordRepository, MaintenanceRepository, ReportRepository,
                                TripRepository, VehicleRepository)
from fleet.repositories.abstractions import (IDriverRepository, IFuelRecordRepository, IMaintenanceRepository,
                                             IReportRepository, ITripRepository, IVehicleRepository)


# one connection and one transaction shared by all repositories
class UnitOfWork:
    def __init__(self, connection: psycopg.Connection, user_id: int) -> None:
        self._connection = connection
        self._finished = False
        self.user_id = user_id
        self.vehicles: IVehicleRepository = VehicleRepository(self)
        self.drivers: IDriverRepository = DriverRepository(self)
        self.trips: ITripRepository = TripRepository(self)
        self.fuel_records: IFuelRecordRepository = FuelRecordRepository(self)
        self.maintenance: IMaintenanceRepository = MaintenanceRepository(self)
        self.reports: IReportRepository = ReportRepository(self)

    @property
    def connection(self) -> psycopg.Connection:
        if self._finished:
            raise RuntimeError("Transaction is already finished")
        return self._connection

    def commit(self) -> None:
        self.connection.commit()
        self._finished = True

    def rollback(self) -> None:
        if not self._finished:
            self._connection.rollback()
            self._finished = True

    def __enter__(self) -> Self:
        return self

    # changes are rolled back if commit() was not called
    def __exit__(self, exc_type: type[BaseException] | None, exc: BaseException | None,
                 tb: TracebackType | None) -> None:
        try:
            self.rollback()
        finally:
            self._connection.close()


class UnitOfWorkFactory:
    def __init__(self, conninfo: str) -> None:
        self._conninfo = conninfo

    # user_id goes to created_by / updated_by / deleted_by through procedures
    def begin(self, user_id: int) -> UnitOfWork:
        connection = psycopg.connect(self._conninfo, autocommit=False)
        return UnitOfWork(connection, user_id)
