#!/usr/bin/env python3
"""Print a workflow node's SQL as a prepared statement, for postgres/tests.

The tests run the queries the workflows actually run, taken from the JSON in
n8n/workflows/, so a test cannot pass against a copy that has drifted from
the deployed workflow.

    python3 infra/scripts/workflow-sql.py <statement> <workflow.json> "<node name>"

prints `PREPARE <statement>(jsonb) AS <query>;`. Every query this is used for
takes its input as one jsonb parameter ($1), the way n8n passes it.
"""

import json
import pathlib
import sys

statement, workflow, node = sys.argv[1:4]
nodes = json.loads(pathlib.Path(workflow).read_text(encoding="utf-8"))["nodes"]
query = next(n["parameters"]["query"] for n in nodes if n["name"] == node)
print(f"PREPARE {statement}(jsonb) AS\n{query.strip().rstrip(';')};")
