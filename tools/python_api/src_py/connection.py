from __future__ import annotations

import warnings
from typing import TYPE_CHECKING, Any, Callable

from . import _kuzu
from .prepared_statement import PreparedStatement
from .query_result import QueryResult

if TYPE_CHECKING:
    import sys
    from types import TracebackType

    from .database import Database
    from .types import Type

    if sys.version_info >= (3, 11):
        from typing import Self
    else:
        from typing_extensions import Self


class Connection:
    """Connection to a database."""

    def __init__(self, database: Database, num_threads: int = 0):
        """
        Initialise kuzu database connection.

        Parameters
        ----------
        database : Database
            Database to connect to.

        num_threads : int
            Maximum number of threads to use for executing queries.

        """
        self._connection: Any = None  # (type: _kuzu.Connection from pybind11)
        self.database = database
        self.num_threads = num_threads
        self.is_closed = False
        self.init_connection()

    def __getstate__(self) -> dict[str, Any]:
        state = {
            "database": self.database,
            "num_threads": self.num_threads,
            "_connection": None,
        }
        return state

    def init_connection(self) -> None:
        """Establish a connection to the database, if not already initalised."""
        if self.is_closed:
            error_msg = "Connection is closed."
            raise RuntimeError(error_msg)
        self.database.init_database()
        if self._connection is None:
            self._connection = _kuzu.Connection(self.database._database, self.num_threads)  # type: ignore[union-attr]

    def set_max_threads_for_exec(self, num_threads: int) -> None:
        """
        Set the maximum number of threads for executing queries.

        Parameters
        ----------
        num_threads : int
            Maximum number of threads to use for executing queries.

        """
        self.init_connection()
        self._connection.set_max_threads_for_exec(num_threads)

    def close(self) -> None:
        """
        Close the connection.

        Note: Call to this method is optional. The connection will be closed
        automatically when the object goes out of scope.
        """
        if self._connection is not None:
            self._connection.close()
        self._connection = None
        self.is_closed = True

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        exc_traceback: TracebackType | None,
    ) -> None:
        self.close()

    def execute(
        self,
        query: str | PreparedStatement,
        parameters: dict[str, Any] | None = None,
    ) -> QueryResult | list[QueryResult]:
        """
        Execute a query.

        Parameters
        ----------
        query : str | PreparedStatement
            A prepared statement or a query string.
            If a query string is given, a prepared statement will be created
            automatically.

        parameters : dict[str, Any]
            Parameters for the query.

        Returns
        -------
        QueryResult
            Query result.

        """
        if parameters is None:
            parameters = {}

        self.init_connection()
        if not isinstance(parameters, dict):
            msg = f"Parameters must be a dict; found {type(parameters)}."
            raise RuntimeError(msg)  # noqa: TRY004

        if len(parameters) == 0 and isinstance(query, str):
            query_result_internal = self._connection.query(query)
        else:
            prepared_statement = self._prepare(query, parameters) if isinstance(query, str) else query
            query_result_internal = self._connection.execute(prepared_statement._prepared_statement, parameters)
        if not query_result_internal.isSuccess():
            raise RuntimeError(query_result_internal.getErrorMessage())
        current_query_result = QueryResult(self, query_result_internal)
        if not query_result_internal.hasNextQueryResult():
            return current_query_result
        all_query_results = [current_query_result]
        while query_result_internal.hasNextQueryResult():
            query_result_internal = query_result_internal.getNextQueryResult()
            if not query_result_internal.isSuccess():
                raise RuntimeError(query_result_internal.getErrorMessage())
            all_query_results.append(QueryResult(self, query_result_internal))
        return all_query_results

    def _prepare(
        self,
        query: str,
        parameters: dict[str, Any] | None = None,
    ) -> PreparedStatement:
        """
        The only parameters supported during prepare are dataframes.
        Any remaining parameters will be ignored and should be passed to execute().
        """  # noqa: D401
        return PreparedStatement(self, query, parameters)

    def prepare(
        self,
        query: str,
        parameters: dict[str, Any] | None = None,
    ) -> PreparedStatement:
        """
        Create a prepared statement for a query.

        Parameters
        ----------
        query : str
            Query to prepare.

        parameters : dict[str, Any]
            Parameters for the query.

        Returns
        -------
        PreparedStatement
            Prepared statement.

        """
        warnings.warn(
            "The use of separate prepare + execute of queries is deprecated. "
            "Please using a single call to the execute() API instead.",
            DeprecationWarning,
            stacklevel=2,
        )
        return self._prepare(query, parameters)

    def _get_node_property_names(self, table_name: str) -> dict[str, Any]:
        LIST_START_SYMBOL = "["
        LIST_END_SYMBOL = "]"
        self.init_connection()
        query_result = self.execute(f"CALL table_info('{table_name}') RETURN *;")
        results = {}
        while query_result.has_next():
            row = query_result.get_next()
            prop_name = row[1]
            prop_type = row[2]
            is_primary_key = row[4] is True
            dimension = prop_type.count(LIST_START_SYMBOL)
            splitted = prop_type.split(LIST_START_SYMBOL)
            shape = []
            for s in splitted:
                if LIST_END_SYMBOL not in s:
                    continue
                s = s.split(LIST_END_SYMBOL)[0]
                if s != "":
                    shape.append(int(s))
            prop_type = splitted[0]
            results[prop_name] = {
                "type": prop_type,
                "dimension": dimension,
                "is_primary_key": is_primary_key,
            }
            if len(shape) > 0:
                results[prop_name]["shape"] = tuple(shape)
        return results

    def _get_node_table_names(self) -> list[Any]:
        results = []
        self.init_connection()
        query_result = self.execute("CALL show_tables() RETURN *;")
        while query_result.has_next():
            row = query_result.get_next()
            if row[2] == "NODE":
                results.append(row[1])
        return results

    def _get_rel_table_names(self) -> list[dict[str, Any]]:
        results = []
        self.init_connection()
        tables_result = self.execute("CALL show_tables() RETURN *;")
        while tables_result.has_next():
            row = tables_result.get_next()
            if row[2] == "REL":
                name = row[1]
                connections_result = self.execute(f"CALL show_connection({name!r}) RETURN *;")
                src_dst_row = connections_result.get_next()
                src_node = src_dst_row[0]
                dst_node = src_dst_row[1]
                results.append({"name": name, "src": src_node, "dst": dst_node})
        return results

    def set_query_timeout(self, timeout_in_ms: int) -> None:
        """
        Set the query timeout value in ms for executing queries.

        Parameters
        ----------
        timeout_in_ms : int
            query timeout value in ms for executing queries.

        """
        self.init_connection()
        self._connection.set_query_timeout(timeout_in_ms)

    def interrupt(self) -> None:
        """
        Interrupts execution of the current query.

        If there is no currently executing query, this function does nothing.
        """
        self._connection.interrupt()

    def create_function(
        self,
        name: str,
        udf: Callable[[...], Any],
        params_type: list[Type | str] | None = None,
        return_type: Type | str = "",
        *,
        default_null_handling: bool = True,
        catch_exceptions: bool = False,
    ) -> None:
        """
        Set a User Defined Function (UDF) for use in cypher queries.

        Parameters
        ----------
        name: str
            name of function

        udf: Callable[[...], Any]
            function to be executed

        params_type: Optional[list[Type]]
            list of Type enums to describe the input parameters

        return_type: Optional[Type]
            a Type enum to describe the returned value

        default_null_handling: Optional[bool]
            if true, when any parameter is null, the resulting value will be null

        catch_exceptions: Optional[bool]
            if true, when an exception is thrown from python, the function output will be null
            Otherwise, the exception will be rethrown
        """
        if params_type is None:
            params_type = []
        parsed_params_type = [x if type(x) is str else x.value for x in params_type]
        if type(return_type) is not str:
            return_type = return_type.value

        self._connection.create_function(
            name=name,
            udf=udf,
            params_type=parsed_params_type,
            return_value=return_type,
            default_null=default_null_handling,
            catch_exceptions=catch_exceptions,
        )

    def remove_function(self, name: str) -> None:
        """
        Remove a User Defined Function (UDF).

        Parameters
        ----------
        name: str
            name of function to be removed.
        """
        self._connection.remove_function(name)
