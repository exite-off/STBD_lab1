import json
import os
import random
import string
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

from psycopg import errors

from fleet.db import UnitOfWorkFactory
from fleet.models import NewDriver, NewVehicle

DEFAULT_CONNINFO = ("host=localhost port=5432 dbname=fleet_db user=postgres password=postgres "
                    "options='-c search_path=fleet,public'")

# users from 07_seed.sql
ADMIN_ID = 1
DISPATCHER_ID = 2
MECHANIC_ID = 3


def section(title: str) -> None:
    print(f"\n=== {title} ===")


def random_vin() -> str:
    chars = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"
    return "".join(random.choices(chars, k=17))


def short(text: str, limit: int = 110) -> str:
    return text if len(text) <= limit else text[:limit] + "..."


def main() -> None:
    factory = UnitOfWorkFactory(os.environ.get("FLEET_DB", DEFAULT_CONNINFO))
    today = date.today()

    # random numbers so the demo can be run again
    plate = f"KA{random.randint(1000, 9999)}AX"
    vin = random_vin()
    license_number = f"BXA{random.randint(100000, 999999)}"

    section("1. Active vehicles (v_vehicles)")
    with factory.begin(DISPATCHER_ID) as uow:
        for v in uow.vehicles.get_all():
            name = f"{v.manufacturer} {v.model}"
            print(f"  #{v.id:<3} {v.plate_number:<9} {name:<24} {v.status:<10} {v.odometer_km:>8} km")

    section("2. New driver + new vehicle + assignment + trip in one transaction")
    with factory.begin(DISPATCHER_ID) as uow:
        driver_id = uow.drivers.add(NewDriver(
            department_id=1, last_name="Doroshenko", first_name="Maksym", middle_name="Ihorovych",
            birth_date=date(1991, 5, 14), phone="+380671234567", email="doroshenko@fleet.ua",
            license_number=license_number, license_expiry=date(2033, 5, 14)))
        uow.drivers.add_license_category(driver_id, "B", date(2010, 6, 1))
        uow.drivers.add_license_category(driver_id, "C", date(2014, 3, 1))

        vehicle_id = uow.vehicles.add(NewVehicle(
            model_id=5, department_id=1, plate_number=plate, vin=vin, manufacture_year=2024, color="Grey",
            odometer_km=1200, purchase_date=today, purchase_price=Decimal("3150000")))
        uow.vehicles.assign_driver(vehicle_id, driver_id, today)

        trip_id = uow.trips.plan(vehicle_id, driver_id, 3, "Delivery to Zhytomyr", datetime.now(UTC) + timedelta(hours=1))
        uow.commit()
        print(f"  Driver #{driver_id}, vehicle #{vehicle_id} ({plate}), trip #{trip_id} saved")

    section("3. Trip execution: triggers change vehicle status and odometer")
    with factory.begin(DISPATCHER_ID) as uow:
        uow.trips.start(trip_id)
        on_trip = uow.vehicles.get_by_id(vehicle_id)
        print(f"  After start: {on_trip.plate_number} status={on_trip.status}, odometer={on_trip.odometer_km}")

        uow.trips.complete(trip_id, on_trip.odometer_km + 142, "Delivered on time")
        uow.fuel_records.add(vehicle_id, driver_id, Decimal("34.5"), Decimal("54.90"), "OKKO Zhytomyr")
        uow.commit()

    with factory.begin(DISPATCHER_ID) as uow:
        v = uow.vehicles.get_by_id(vehicle_id)
        t = uow.trips.get_by_id(trip_id)
        print(f"  After completion: status={v.status}, odometer={v.odometer_km}, changed by: {v.updated_by}")
        print(f"  Trip #{t.id}: {t.status}, {t.distance_km} km, {t.route_name}")
        for f in uow.fuel_records.get_by_vehicle(vehicle_id):
            print(f"  Refuel: {f.liters} l x {f.price_per_liter} = {f.total_cost} UAH ({f.station}), "
                  f"added by: {f.created_by}")

    section("4. Rollback: driver without category D can not drive a bus")
    temp_license = f"BXB{random.randint(100000, 999999)}"
    with factory.begin(DISPATCHER_ID) as uow:
        try:
            new_id = uow.drivers.add(NewDriver(
                department_id=2, last_name="Hnatiuk", first_name="Roman", middle_name=None,
                birth_date=date(1995, 2, 2), phone="+380679998877", email=None,
                license_number=temp_license, license_expiry=date(2034, 2, 2)))
            uow.drivers.add_license_category(new_id, "B", date(2014, 1, 1))
            print(f"  Driver #{new_id} added in transaction, planning a bus trip...")

            uow.trips.plan(7, new_id, 5, "Airport transfer", datetime.now(UTC) + timedelta(hours=2))
            uow.commit()
        except errors.RaiseException as ex:
            print(f"  DB error: {ex.diag.message_primary}")
            uow.rollback()

    with factory.begin(DISPATCHER_ID) as uow:
        found = uow.drivers.get_by_license(temp_license)
        print("  Transaction rolled back: driver is not in the database" if found is None
              else "  Driver is still in the database!")

    section("5. Maintenance (mechanic)")
    with factory.begin(MECHANIC_ID) as uow:
        record_id = uow.maintenance.schedule(vehicle_id, 2, 5, today, "First diagnostics")
        uow.maintenance.start(record_id)
        print(f"  Vehicle status during maintenance: {uow.vehicles.get_by_id(vehicle_id).status}")
        uow.maintenance.complete(record_id, Decimal("2400"), "No issues found")
        uow.commit()

    with factory.begin(MECHANIC_ID) as uow:
        for m in uow.maintenance.get_by_vehicle(vehicle_id):
            print(f"  {m.maintenance_type}: {m.status}, {m.cost} UAH, {m.service_center}, changed by: {m.updated_by}")
        print(f"  Vehicle status after maintenance: {uow.vehicles.get_by_id(vehicle_id).status}")

    section("6. Driver soft delete and restore")
    with factory.begin(ADMIN_ID) as uow:
        uow.drivers.update(driver_id, phone="+380670000001")
        uow.drivers.delete(driver_id)
        print(f"  Among active: {'no' if uow.drivers.get_by_id(driver_id) is None else 'yes'}")
        for d in uow.drivers.get_deleted():
            print(f"  Recycle bin: #{d.id} {d.title}, deleted by {d.deleted_by} {d.deleted_at:%Y-%m-%d %H:%M}")

        uow.drivers.restore(driver_id)
        restored = uow.drivers.get_by_id(driver_id)
        print(f"  Restored: {restored.full_name}, categories {restored.categories}, "
              f"vehicle {restored.assigned_vehicle or '-'}")
        uow.commit()

    section("7. Vehicle change history (audit_log via fn_record_history)")
    with factory.begin(ADMIN_ID) as uow:
        for h in uow.reports.get_history("vehicles", vehicle_id):
            changes = short(json.dumps(h.changes, ensure_ascii=False, default=str))
            print(f"  {h.changed_at:%H:%M:%S} {h.operation:<11} {h.changed_by:<16} {changes}")

    section("8. Reports")
    with factory.begin(ADMIN_ID) as uow:
        print("  Expiring documents:")
        for d in uow.reports.get_expiring_documents():
            print(f"    {d.document_type:<18} {d.owner:<18} {d.document_number:<14} {d.expires_on} ({d.days_left} days)")

        print("  Vehicle statistics:")
        for s in uow.reports.get_vehicle_stats():
            consumption = s.avg_consumption if s.avg_consumption is not None else "-"
            print(f"    {s.plate_number:<9} trips {s.trips_completed:>2}, {s.trips_km:>5} km, "
                  f"fuel {s.fuel_cost:>9} UAH, service {s.maintenance_cost:>9} UAH, {consumption} l/100km")

        year_ago = today - timedelta(days=365)
        c = uow.reports.get_vehicle_costs(6, year_ago, today)
        consumption = uow.reports.get_fuel_consumption(6, year_ago, today)
        print(f"  Vehicle #6 costs per year: fuel {c.fuel_cost}, service {c.maintenance_cost}, "
              f"fines {c.fines_amount}, insurance {c.insurance_cost}, total {c.total_cost} UAH")
        print(f"  Vehicle #6 average consumption: {consumption} l/100 km")

        plates = " ".join(v.plate_number for v in uow.vehicles.get_available_for_driver(1))
        print(f"  Available vehicles for driver #1 (fn_available_vehicles): {plates}")

        uow.reports.refresh_statistics()
        uow.commit()


if __name__ == "__main__":
    main()
