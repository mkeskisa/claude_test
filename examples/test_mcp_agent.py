"""Offline tests: real agent runner and MCP subprocess, no OpenAI requests."""

import asyncio
from contextlib import closing, redirect_stderr
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from agents.exceptions import MaxTurnsExceeded
from agents.testing import ScriptedModel, assistant_message, function_call

from mcp_agent import (
    COHORT_PARAMS, DEFAULT_DATABASE, DRUG_SQL, PREVALENCE_SQL, ROOT,
    checked_call, main, open_server, run_agent, run_demo,
)


class AgentExampleTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.database = Path(directory.name) / "synthetic.sqlite"
        with closing(sqlite3.connect(self.database)) as con, con:
            con.executescript("""
                CREATE TABLE patient (subject_id INTEGER PRIMARY KEY, race TEXT, gender TEXT);
                INSERT INTO patient VALUES
                    (1, 'Black', 'Male'), (2, 'Black', 'Male'), (3, 'White', 'Male'),
                    (4, 'Black', 'Male'), (5, 'Black', 'Female');
                CREATE TABLE condition_occurrence (subject_id INTEGER, condition_concept_id INTEGER);
                INSERT INTO condition_occurrence VALUES
                    (1, 319835), (1, 319835), (2, 319835), (3, 319835), (4, 123);
                CREATE TABLE drug_exposure
                    (subject_id INTEGER, drug_concept_id INTEGER, drug_source_value TEXT);
                INSERT INTO drug_exposure VALUES
                    (1, 10, 'Drug A'), (1, 10, 'Drug A alias'), (1, 20, 'Drug B'),
                    (3, 10, 'Drug A'), (4, 10, 'Drug A');
            """)

    def demo(self):
        async def check():
            async with open_server(self.database) as server:
                return await run_demo(server)
        return asyncio.run(check())

    def test_real_mcp_demo_correct_denominators_and_no_join_inflation(self):
        report = self.demo()
        self.assertEqual(report["hypertension_prevalence"]["result"]["rows"], [
            ["All patients", 3, 5, 60.0], ["Black male patients", 2, 3, 66.7],
        ])
        self.assertEqual(report["cohort_size"]["result"]["rows"], [[2]])
        self.assertEqual(report["cohort_drugs"]["result"]["rows"], [
            [10, "Drug A", 2, 1, 50.0], [20, "Drug B", 1, 1, 50.0],
        ])

    def test_empty_population_has_undefined_prevalence(self):
        with closing(sqlite3.connect(self.database)) as con, con:
            con.execute("DELETE FROM patient")
        report = self.demo()
        self.assertEqual(report["hypertension_prevalence"]["result"]["rows"], [
            ["All patients", 0, 0, None], ["Black male patients", 0, 0, None],
        ])
        self.assertEqual(report["cohort_size"]["result"]["rows"], [[0]])
        self.assertEqual(report["cohort_drugs"]["result"]["rows"], [])

    def test_no_diagnoses_is_zero_not_undefined(self):
        with closing(sqlite3.connect(self.database)) as con, con:
            con.execute("DELETE FROM condition_occurrence")
        report = self.demo()
        self.assertEqual(report["hypertension_prevalence"]["result"]["rows"], [
            ["All patients", 0, 5, 0.0], ["Black male patients", 0, 3, 0.0],
        ])
        self.assertEqual(report["cohort_drugs"]["result"]["rows"], [])

    def test_mcp_adapter_still_denies_writes(self):
        async def check():
            async with open_server(self.database) as server:
                denied = await server.call_tool("query", {"sql": "DELETE FROM patient"})
                self.assertTrue(denied.isError)
                count = await checked_call(server, "query", {"sql": "SELECT COUNT(*) FROM patient"})
                self.assertEqual(count["rows"], [[5]])
        asyncio.run(check())

    def test_real_agent_loop_with_scripted_model(self):
        requests = [
            ("list_tables", {}),
            ("describe_table", {"name": "patient"}),
            ("describe_table", {"name": "condition_occurrence"}),
            ("describe_table", {"name": "drug_exposure"}),
            ("query", {"sql": PREVALENCE_SQL, "params": COHORT_PARAMS, "max_rows": 100}),
            ("query", {"sql": DRUG_SQL, "params": COHORT_PARAMS, "max_rows": 100}),
        ]
        model = ScriptedModel([
            [function_call(name, arguments, call_id=f"call_{i}")]
            for i, (name, arguments) in enumerate(requests)
        ] + [[assistant_message("Offline agent loop completed.")]])

        async def check():
            async with open_server(self.database) as server:
                return await run_agent(server, "Analyze the synthetic data.", model=model)

        result = asyncio.run(check())
        self.assertEqual(result.final_output, "Offline agent loop completed.")
        self.assertEqual(model.remaining_steps, 0)
        self.assertEqual(len(model.calls), 7)
        outputs = [item for item in model.calls[-1].input if item.get("type") == "function_call_output"]
        self.assertEqual(json.loads(outputs[-2]["output"])["rows"][0], ["All patients", 3, 5, 60.0])
        self.assertEqual(json.loads(outputs[-1]["output"])["rows"][0], [10, "Drug A", 2, 1, 50.0])
        for call in model.calls:
            self.assertTrue(call.tracing.is_disabled())
            self.assertFalse(call.model_settings.store)
            self.assertEqual({tool.name for tool in call.tools}, {"list_tables", "describe_table", "query"})

    def test_max_turns_stops_agent_loop(self):
        model = ScriptedModel([[function_call("list_tables", {}, call_id="only_call")]])

        async def check():
            async with open_server(self.database) as server:
                await run_agent(server, "Inspect the database.", model=model, max_turns=1)

        with self.assertRaises(MaxTurnsExceeded):
            asyncio.run(check())

    def test_mcp_errors_missing_data_and_truncation_are_not_silently_reported(self):
        for result in (
            SimpleNamespace(isError=True, content="query failed"),
            SimpleNamespace(isError=False, structuredContent=None),
            SimpleNamespace(isError=False, structuredContent={"truncated": True}),
        ):
            with self.subTest(result=result), self.assertRaises(RuntimeError):
                server = SimpleNamespace(call_tool=AsyncMock(return_value=result))
                asyncio.run(checked_call(server, "query", {}))

    def test_missing_database_is_not_created(self):
        path = self.database.with_name("missing.sqlite")
        with self.assertRaises(FileNotFoundError):
            open_server(path)
        self.assertFalse(path.exists())

    def test_server_paths_are_absolute_and_api_key_is_not_forwarded(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "test-not-a-real-key"}):
            server = open_server(self.database)
        self.assertEqual(server.params.command, sys.executable)
        self.assertEqual(server.params.cwd, str(ROOT))
        self.assertEqual(server.params.env, {})
        self.assertTrue(Path(server.params.args[0]).is_absolute())
        self.assertTrue(DEFAULT_DATABASE.is_absolute())

    def test_cli_demo_from_another_directory_without_key(self):
        env = dict(os.environ)
        env.pop("OPENAI_API_KEY", None)
        before = self.database.read_bytes()
        result = subprocess.run(
            [sys.executable, str(ROOT / "examples" / "mcp_agent.py"), "--demo", "--db", str(self.database)],
            cwd=self.database.parent, env=env, capture_output=True, text=True, timeout=45,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["cohort_size"]["result"]["rows"], [[2]])
        self.assertEqual(self.database.read_bytes(), before)

    def test_live_cli_requires_key_and_valid_arguments(self):
        for extra, message in (
            ([], "No OPENAI_API_KEY"),
            (["--max-turns", "0"], "must be positive"),
            (["--demo", "--question", "Count patients"], "uses fixed queries"),
            (["--question", " "], "must not be empty"),
        ):
            errors = io.StringIO()
            with self.subTest(extra=extra), patch.dict(os.environ, {"OPENAI_API_KEY": ""}), redirect_stderr(errors):
                with self.assertRaises(SystemExit) as raised:
                    main(["--db", str(self.database), *extra])
                self.assertEqual(raised.exception.code, 2)
                self.assertIn(message, errors.getvalue())


if __name__ == "__main__":
    unittest.main()
