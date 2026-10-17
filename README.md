# Лабораторна робота 1. Система управління автопарком (Варіант 8)

СУБД: **PostgreSQL 16** (працює на 13+). Код: **Python 3.14+**, бібліотека **psycopg 3**.

```
lab1/
├── diagram/
│   └── car_fleet.svg     ER-діаграма, експорт з dbdiagram.io
├── docker-compose.yml    PostgreSQL 16 у Docker, БД створюється автоматично
├── docker/init.sql       запускає sql/00_run_all.sql під час першого старту
├── sql/
│   ├── 00_run_all.sql    запускає всі скрипти по черзі
│   ├── 01_schema.sql     таблиці, типи, обмеження
│   ├── 02_functions.sql  користувацькі функції
│   ├── 03_triggers.sql   тригери
│   ├── 04_views.sql      розрізи даних (View) + матеріалізований View
│   ├── 05_procedures.sql збережені процедури + табличні функції
│   ├── 06_indexes.sql    індекси
│   ├── 07_seed.sql       тестові дані
│   └── 08_demo.sql       демонстрація роботи
└── app/                  консольний застосунок: Repository + Unit of Work
    ├── pyproject.toml
    └── fleet/
        ├── __main__.py       демонстраційний сценарій
        ├── models.py         dataclass-моделі (поля = стовпці View)
        ├── db/unit_of_work.py
        └── repositories/     base.py, abstractions.py (Protocol), vehicles, drivers, trips, fuel_records, maintenance, reports
```

## 1. Вимоги до системи

Автопарк підприємства має кілька підрозділів. Система повинна:

1. Зберігати користувачів системи (адміністратор, диспетчер, механік, бухгалтер) з ролями.
2. Вести облік авто: модель, виробник, тип, вид пального, номер, VIN, пробіг, статус (вільне, в рейсі, на ТО, списане), підрозділ.
3. Вести облік водіїв: персональні дані, посвідчення (номер, термін дії) і відкриті категорії (B, C1, C, CE, D).
4. Не дозволяти водію вести авто, якщо в нього немає потрібної категорії або посвідчення прострочене.
5. Закріплювати авто за водієм на період; одне авто не може бути закріплене за двома водіями одночасно.
6. Планувати, починати, завершувати та скасовувати рейси за маршрутами; авто і водій не можуть бути одночасно у двох рейсах.
7. Автоматично змінювати статус авто і пробіг під час рейсу та обслуговування; пробіг не може зменшуватись.
8. Облік заправок (об'єм не більше бака, тип пального як у моделі), технічного обслуговування в сервісних центрах, страхових полісів (ОСЦПВ, КАСКО) та штрафів.
9. Видалені авто, водії, маршрути, сервісні центри, записи ТО і користувачі не зникають, а потрапляють у "кошик" (**soft delete**) з можливістю відновлення.
10. Для основних сутностей зберігати дату створення/останньої зміни та **користувача, що змінив**, а також повну історію змін (журнал аудиту).
11. Звіти: документи, що спливають; статистика по авто; витрати по авто; середня витрата пального; місячна статистика підрозділів.

## 2. Сутності (22)

| # | Таблиця | Призначення | Soft delete | Аудит |
|---|---|---|:-:|:-:|
| 1 | roles | ролі користувачів | | |
| 2 | users | користувачі системи | ✔ | |
| 3 | departments | підрозділи | | |
| 4 | license_categories | категорії посвідчень | | |
| 5 | vehicle_types | типи ТЗ + потрібна категорія | | |
| 6 | manufacturers | виробники | | |
| 7 | fuel_types | види пального | | |
| 8 | vehicle_models | моделі | | |
| 9 | vehicles | транспортні засоби | ✔ | ✔ |
| 10 | drivers | водії | ✔ | ✔ |
| 11 | driver_licenses | категорії водія | | |
| 12 | vehicle_assignments | закріплення авто за водієм | | |
| 13 | routes | маршрути | ✔ | |
| 14 | trips | рейси | | ✔ |
| 15 | fuel_records | заправки | | ✔ |
| 16 | service_centers | сервісні центри | ✔ | |
| 17 | maintenance_types | види ТО | | |
| 18 | maintenance_records | записи ТО | ✔ | ✔ |
| 19 | insurance_companies | страхові компанії | | |
| 20 | insurance_policies | страхові поліси | | ✔ |
| 21 | fines | штрафи | | ✔ |
| 22 | audit_log | журнал змін (jsonb) | | |

**Soft delete:** поля `is_deleted`, `deleted_at`, `deleted_by`. Звичайний `DELETE` перехоплює тригер і перетворює його на `UPDATE ... SET is_deleted = true`. Фізичне видалення лише після `SET app.hard_delete = 'on'`.

**Аудит:** поля `created_at`, `created_by`, `updated_at`, `updated_by` заповнює тригер. Користувач передається першим параметром кожної процедури і зберігається в змінній транзакції `app.user_id`. Тригер `trg_fn_audit_log` пише старі та нові значення в `audit_log`.

## 3. Об'єкти БД

### Функції (02_functions.sql, 05_procedures.sql)
| Функція | Що робить |
|---|---|
| `fn_current_user_id()` | id користувача поточної транзакції |
| `fn_set_current_user(id)` | перевіряє і запам'ятовує користувача |
| `fn_driver_can_drive(driver, vehicle, date)` | чи має водій категорію і дійсне посвідчення |
| `fn_vehicle_fuel_consumption(vehicle, from, to)` | середня витрата л/100 км |
| `fn_vehicle_costs(vehicle, from, to)` | табличка витрат: пальне, ТО, штрафи, страхування |
| `fn_record_history(table, id)` | історія змін запису: хто, коли, які поля |
| `fn_available_vehicles(driver)` | вільні авто, якими може керувати водій |
| `fn_driver_trips(driver, from, to)` | рейси водія за період |

### Тригери (03_triggers.sql)
| Тригер | Таблиці | Що робить |
|---|---|---|
| `trg_*_audit_fields` | 7 таблиць з аудитом | created/updated + користувач |
| `trg_*_audit_log` | ті самі | запис у `audit_log` (INSERT/UPDATE/SOFT_DELETE/RESTORE/DELETE) |
| `trg_*_soft_delete` | 6 таблиць | DELETE → soft delete |
| `trg_vehicles_odometer_guard` | vehicles | пробіг не зменшується |
| `trg_trips_validate` | trips | категорія, видалені/зайняті авто і водії, пробіг на старті |
| `trg_trips_status_sync` | trips | статус авто `on_trip`/`available`, оновлення пробігу |
| `trg_maintenance_status_sync` | maintenance_records | статус авто `in_service`/`available` |
| `trg_fuel_records_validate` | fuel_records | тип пального, об'єм бака |

### Розрізи даних (04_views.sql)
`v_vehicles`, `v_vehicles_deleted`, `v_drivers`, `v_drivers_deleted`, `v_trips`, `v_fuel_records`, `v_maintenance`, `v_expiring_documents`, `v_vehicle_stats`, матеріалізований `mv_department_monthly_stats`.

### Збережені процедури (05_procedures.sql)
- авто: `sp_vehicle_create`, `sp_vehicle_update`, `sp_vehicle_delete`, `sp_vehicle_restore`, `sp_vehicle_assign`
- водії: `sp_driver_create`, `sp_driver_update`, `sp_driver_add_license`, `sp_driver_delete`, `sp_driver_restore`
- рейси: `sp_trip_plan`, `sp_trip_start`, `sp_trip_complete`, `sp_trip_cancel`
- пальне: `sp_fuel_record_add`
- ТО: `sp_maintenance_schedule`, `sp_maintenance_start`, `sp_maintenance_complete`, `sp_maintenance_delete`
- штрафи: `sp_fine_register` (водія визначає за рейсом), `sp_fine_pay`
- `sp_refresh_statistics` — оновлення матеріалізованого View

Разом: 8 функцій + 9 тригерних функцій + 10 View + 22 процедури.

## 4. Індекси (06_indexes.sql)

| Тип | Приклади |
|---|---|
| B-tree унікальний частковий + за виразом | `ux_vehicles_plate_active ON vehicles (upper(plate_number)) WHERE NOT is_deleted` — номер унікальний лише серед не видалених |
| B-tree складений | `ix_trips_vehicle_start (vehicle_id, actual_start DESC)` |
| B-tree покривний (INCLUDE) | `ix_fuel_vehicle_date (vehicle_id, refuel_date) INCLUDE (liters, total_cost)` |
| B-tree частковий | `ix_trips_in_progress ... WHERE status = 'in_progress'` |
| Hash | `ix_drivers_phone_hash`, `ix_vehicles_vin_hash` |
| GIN | `ix_audit_log_new_data_gin (new_data jsonb_path_ops)`, `ix_drivers_last_name_trgm (last_name gin_trgm_ops)` |
| BRIN | `ix_trips_planned_brin`, `ix_audit_log_changed_brin` |
| GiST | обмеження `ex_assignments_vehicle_overlap` (EXCLUDE USING gist, періоди не перетинаються) |

## 5. Код: Repository + Unit of Work

- `db/unit_of_work.py` — `UnitOfWork` тримає одне з'єднання і одну транзакцію на всі репозиторії; використовується як контекстний менеджер `with factory.begin(user_id) as uow:`. `uow.commit()` фіксує, вихід з `with` без коміту відкочує. `UnitOfWorkFactory` створює UoW від імені користувача.
- `repositories/base.py` — `RepositoryBase` дозволяє лише `CALL sp_*` для змін і `SELECT` з `v_*` / `fn_*` для читання. Користувач UoW автоматично передається першим параметром процедури.
- `repositories/abstractions.py` — контракти репозиторіїв (`typing.Protocol`).
- Репозиторії: `uow.vehicles`, `uow.drivers`, `uow.trips`, `uow.fuel_records`, `uow.maintenance`, `uow.reports`.

`fleet/__main__.py` показує: читання з View; створення водія, авто, закріплення і рейсу в одній транзакції; роботу тригерів (статус, пробіг); **відкат транзакції**, коли тригер забороняє рейс; ТО від імені механіка; soft delete і відновлення; історію змін з іменами користувачів; звіти.

## 6. Запуск

1. Створити БД.

   **Docker:**
   ```
   docker compose up -d
   ```
   Контейнер `fleet_db` з PostgreSQL 16 на порту 5432 (користувач `postgres`, пароль `postgres`) під час першого запуску сам виконує `sql/00_run_all.sql`.
   Демо-скрипт: `docker exec -it fleet_db psql -U postgres -d fleet_db -f /sql/08_demo.sql`.
   Перестворити БД з нуля: `docker compose down -v`, потім знову `docker compose up -d`.


2. Застосунок (потрібен Python 3.14+):
   ```
   cd app
   py -3.14 -m venv .venv
   .venv\Scripts\activate
   pip install -e .
   python -m fleet
   ```
   Рядок підключення за замовчуванням: `host=localhost port=5432 dbname=fleet_db user=postgres password=postgres options='-c search_path=fleet,public'`.
   Інший пароль задається змінною середовища `FLEET_DB` або зміною `DEFAULT_CONNINFO` у `fleet/__main__.py`.
