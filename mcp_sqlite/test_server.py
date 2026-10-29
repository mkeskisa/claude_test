import asyncio
from contextlib import closing
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from server import SQLiteReader


class SQLiteMCPTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.database = Path(self.directory.name) / "sample.sqlite"
        with closing(sqlite3.connect(self.database)) as con, con:
            con.executescript("""
                CREATE TABLE patient (subject_id INTEGER PRIMARY KEY, gender TEXT);
                INSERT INTO patient VALUES (1, 'Male'), (2, 'Female');
                CREATE TABLE drug_exposure (
                    subject_id INTEGER REFERENCES patient(subject_id), drug_name TEXT
                );
                INSERT INTO drug_exposure VALUES (1, 'Example'), (1, 'Example');
            """)
        self.reader = SQLiteReader(self.database)

    def test_tables_and_schema(self):
        self.assertEqual(self.reader.list_tables()["rows"], [["drug_exposure", "table"], ["patient", "table"]])
        schema = self.reader.describe_table("drug_exposure")
        self.assertEqual(schema["columns"][0]["name"], "subject_id")
        self.assertEqual(schema["foreign_keys"][0]["table"], "patient")
        with self.assertRaises(ValueError):
            self.reader.describe_table('patient"; DROP TABLE patient; --')

    def test_bound_values_and_cte(self):
        result = self.reader.query("""
            WITH cohort AS (SELECT subject_id FROM patient WHERE gender = ?)
            SELECT COUNT(*) AS exposures, COUNT(DISTINCT d.subject_id) AS patients
            FROM drug_exposure d JOIN cohort p ON d.subject_id = p.subject_id
        """, ["Male"])
        self.assertEqual(result["rows"], [[2, 1]])
        self.assertFalse(result["truncated"])
        self.assertEqual(self.reader.query("SELECT * FROM patient WHERE gender = ?", ["' OR 1=1 --"])["rows"], [])

    def test_limits_and_duplicate_column_names(self):
        self.assertTrue(self.reader.query("SELECT * FROM patient", max_rows=1)["truncated"])
        self.assertFalse(self.reader.query("SELECT * FROM patient", max_rows=2)["truncated"])
        self.assertEqual(self.reader.query("SELECT 1 AS n, 2 AS n")["rows"], [[1, 2]])
        self.assertTrue(self.reader.query("SELECT hex(zeroblob(60000))")["truncated"])
        for value in (0, 501, True):
            with self.assertRaises(ValueError):
                self.reader.query("SELECT 1", max_rows=value)

    def test_changes_and_external_access_are_denied(self):
        statements = [
            "DELETE FROM patient",
            "UPDATE patient SET gender = 'Changed'",
            "INSERT INTO patient VALUES (3, 'Other')",
            "DROP TABLE patient",
            "WITH x AS (SELECT 1) DELETE FROM patient",
            "ATTACH DATABASE ':memory:' AS other",
            "PRAGMA query_only = OFF",
            "PRAGMA writable_schema = ON",
            "SELECT load_extension('missing')",
            "SELECT 1; DELETE FROM patient",
            "BEGIN",
        ]
        for sql in statements:
            with self.subTest(sql=sql), self.assertRaises(sqlite3.Error):
                self.reader.query(sql)
        self.assertEqual(self.reader.query("SELECT COUNT(*) FROM patient")["rows"], [[2]])

    def test_missing_database_is_not_created(self):
        missing = self.database.with_name("absent.sqlite")
        with self.assertRaises(FileNotFoundError):
            SQLiteReader(missing)
        self.assertFalse(missing.exists())

    def test_connection_itself_is_read_only(self):
        con = self.reader.connect()
        try:
            con.execute("PRAGMA query_only = OFF")
            with self.assertRaises(sqlite3.OperationalError):
                con.execute("DELETE FROM patient")
        finally:
            con.close()

    def test_slow_queries_are_interrupted(self):
        with patch("server.QUERY_TIMEOUT_SECONDS", 0):
            with self.assertRaisesRegex(sqlite3.OperationalError, "interrupted"):
                self.reader.query("""
                    WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 100000000)
                    SELECT SUM(x) FROM n
                """)

    def test_committed_changes_from_another_connection_are_visible(self):
        with closing(sqlite3.connect(self.database)) as con, con:
            con.execute("INSERT INTO patient VALUES (3, 'Other')")
        self.assertEqual(self.reader.query("SELECT COUNT(*) FROM patient")["rows"], [[3]])

    def test_stdio_protocol(self):
        async def check():
            parameters = StdioServerParameters(
                command=sys.executable,
                args=[str(Path(__file__).with_name("server.py")), "--db", str(self.database)],
            )
            async with stdio_client(parameters) as (read, write):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    tools = (await session.list_tools()).tools
                    self.assertEqual({tool.name for tool in tools}, {"list_tables", "describe_table", "query"})
                    self.assertTrue(all(tool.annotations.readOnlyHint for tool in tools))
                    for name, arguments in (("list_tables", {}), ("describe_table", {"name": "patient"})):
                        self.assertFalse((await session.call_tool(name, arguments)).isError)
                    result = await session.call_tool("query", {"sql": "SELECT COUNT(*) AS n FROM patient"})
                    self.assertFalse(result.isError)
                    self.assertEqual(result.structuredContent["rows"], [[2]])
                    denied = await session.call_tool("query", {"sql": "DELETE FROM patient"})
                    self.assertTrue(denied.isError)

        asyncio.run(check())


if __name__ == "__main__":
    unittest.main()
