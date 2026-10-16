from dataclasses import fields
from typing import TYPE_CHECKING, Any

from psycopg import sql
from psycopg.rows import dict_row

if TYPE_CHECKING:
    from fleet.db.unit_of_work import UnitOfWork

type Row = dict[str, Any]


def to_model[T](model: type[T], row: Row) -> T:
    # takes only the columns the dataclass has
    return model(**{f.name: row[f.name] for f in fields(model)})


# all queries go only through procedures (CALL), views (v_*) and functions (fn_*)
class RepositoryBase:
    def __init__(self, uow: UnitOfWork) -> None:
        self._uow = uow

    def _cursor(self):
        return self._uow.connection.cursor(row_factory=dict_row)

    @staticmethod
    def _call_sql(procedure: str, count: int, returns_id: bool = False) -> sql.Composed:
        params = [sql.Placeholder()] * count
        if returns_id:
            params.append(sql.NULL)
        return sql.SQL("CALL {}({})").format(sql.Identifier(procedure), sql.SQL(", ").join(params))

    # first parameter of every modifying procedure is the user id
    def _call(self, procedure: str, *args: Any) -> None:
        params = (self._uow.user_id, *args)
        with self._cursor() as cur:
            cur.execute(self._call_sql(procedure, len(params)), params)

    # for procedures with INOUT p_id: CALL returns a row with the new id
    def _call_returning_id(self, procedure: str, *args: Any) -> int:
        params = (self._uow.user_id, *args)
        with self._cursor() as cur:
            cur.execute(self._call_sql(procedure, len(params), returns_id=True), params)
            return cur.fetchone()["p_id"]

    # service procedures without user
    def _call_without_user(self, procedure: str) -> None:
        with self._cursor() as cur:
            cur.execute(self._call_sql(procedure, 0))

    def _rows(self, query: str, *args: Any) -> list[Row]:
        with self._cursor() as cur:
            cur.execute(query, args)
            return cur.fetchall()

    def _query[T](self, model: type[T], query: str, *args: Any) -> list[T]:
        return [to_model(model, row) for row in self._rows(query, *args)]

    def _query_one[T](self, model: type[T], query: str, *args: Any) -> T | None:
        rows = self._query(model, query, *args)
        return rows[0] if rows else None

    def _scalar(self, query: str, *args: Any) -> Any:
        rows = self._rows(query, *args)
        return next(iter(rows[0].values())) if rows else None
