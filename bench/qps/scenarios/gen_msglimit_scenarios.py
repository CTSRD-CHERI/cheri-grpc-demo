#!python

import json
import re
from pathlib import Path

UNARY_MESSAGE_LIMIT=200000
STREAM_MESSAGE_LIMIT=200000

# Generate the scenario variants with a fixed message limit that replaces the time limit.
def gen_scenario(path: Path):
    with open(path, "r") as fd:
        data = json.load(fd)
    for scenario in data["scenarios"]:
        if "benchmark_seconds" in scenario:
            del scenario["benchmark_seconds"]
        client_conf = scenario["client_config"]
        is_unary = client_conf["rpc_type"] == "UNARY"
        if is_unary:
            scenario["message_limit"] = UNARY_MESSAGE_LIMIT
        else:
            scenario["message_limit"] = STREAM_MESSAGE_LIMIT

    new_name = path.stem + "_msglimit.json"
    new_path = path.with_name(new_name)
    with open(new_path, "w+") as fd:
        json.dump(data, fd)


def main():
    curdir = Path.cwd()
    for name in curdir.iterdir():
        if name.stem.endswith("_msglimit"):
            # Skip generated files
            continue
        if name.suffix == ".json":
            gen_scenario(name)


if __name__ == "__main__":
    main()
