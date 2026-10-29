"""Exercise all three MCP tools against the existing example database."""

import argparse
import asyncio
import json
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def check(database: Path):
    parameters = StdioServerParameters(
        command=sys.executable,
        args=[str(Path(__file__).with_name("server.py").resolve()), "--db", str(database.resolve())],
    )
    async with stdio_client(parameters) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            discovered = [tool.name for tool in (await session.list_tools()).tools]
            assert set(discovered) == {"list_tables", "describe_table", "query"}

            async def call(name, arguments):
                result = await session.call_tool(name, arguments)
                if result.isError:
                    raise RuntimeError(result.content)
                return result.structuredContent

            tables = await call("list_tables", {})
            schema = await call("describe_table", {"name": "patient"})
            count = await call("query", {"sql": "SELECT COUNT(*) AS patients FROM patient"})
            drugs = await call("query", {
                "sql": """
                    WITH cohort AS (
                        SELECT p.subject_id FROM patient p
                        WHERE p.race = ? AND p.gender = ? AND EXISTS (
                            SELECT 1 FROM condition_occurrence c
                            WHERE c.subject_id = p.subject_id AND c.condition_concept_id = ?
                        )
                    )
                    SELECT MIN(d.drug_source_value) AS drug_name,
                        COUNT(*) AS exposure_count,
                        COUNT(DISTINCT d.subject_id) AS patient_count
                    FROM drug_exposure d JOIN cohort p ON p.subject_id = d.subject_id
                    GROUP BY d.drug_concept_id
                    ORDER BY exposure_count DESC, patient_count DESC, drug_name
                """,
                "params": ["Black", "Male", 319835],
            })
            print(json.dumps({
                "tools": discovered,
                "tables": tables,
                "patient_columns": [column["name"] for column in schema["columns"]],
                "patient_count": count,
                "hypertension_cohort_drugs": drugs,
            }, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=Path(__file__).resolve().parents[1] / "outputs" / "omop.sqlite")
    asyncio.run(check(parser.parse_args().db))
