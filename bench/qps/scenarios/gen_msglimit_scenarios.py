#!python

import argparse as ap
import json
import re
from pathlib import Path

SCENARIO_PATTERN = r"scenario_dump_cpp_protobuf_(?P<api>sync|async)_(?P<mode>streaming|unary)_qps_unconstrained_(?P<tls>secure|insecure)_(?P<size>[0-9]+)b"

# Generate the scenario variants with a fixed message limit that replaces the time limit.
def gen_scenario(args, data):
    for scenario in data["scenarios"]:
        if "benchmark_seconds" in scenario:
            del scenario["benchmark_seconds"]
        scenario["warmup_seconds"] = args.w

        client_conf = scenario["client_config"]
        is_unary = client_conf["rpc_type"] == "UNARY"
        if is_unary:
            scenario["message_limit"] = args.u
        else:
            scenario["message_limit"] = args.s
    return data


def gen_filename(args, data):
    scenario = data["scenarios"][0]
    client_conf = scenario["client_config"]

    if client_conf["client_type"] == "ASYNC_CLIENT":
        client_type = "async"
    else:
        client_type = "sync"
    if client_conf["rpc_type"] == "UNARY":
        rpc_type = "unary"
        limit = str(args.u)
    else:
        rpc_type = "streaming"
        limit = str(args.s)
    if client_conf["security_params"] is not None:
        tls = "secure"
    else:
        tls = "insecure"
    size = client_conf["payload_config"]["simple_params"]["req_size"]

    nzeros = len(limit) - len(limit.rstrip("0"))
    if nzeros >= 9:
        limit = limit[:-9] + "G"
    elif nzeros >= 6:
        limit = limit[:-6] + "M"
    elif nzeros >= 3:
        limit = limit[:-3] + "K"

    return f"qps_{client_type}_{rpc_type}_{tls}_{size}b_{limit}.json"


def main():
    parser = ap.ArgumentParser("Scenario editor")
    parser.add_argument("-u", type=int, help="Unary message limit", default=200000)
    parser.add_argument("-s", type=int, help="Streaming message limit", default=200000)
    parser.add_argument("-w", type=int, help="Set the warmup period", default=5)
    parser.add_argument("-c", action="store_true", help="Clear the generated scenarios")

    args = parser.parse_args()
    curdir = Path.cwd()
    destdir = curdir / "gen"
    destdir.mkdir(exist_ok=True)

    if args.c:
        for name in destdir.iterdir():
            name.unlink()
        return

    for name in curdir.iterdir():
        m = re.match(SCENARIO_PATTERN, name.stem)
        if m:
            print("Generate scenario based on", name.stem)
            with open(name, "r") as fd:
                data = json.load(fd)
            dest_file = gen_filename(args, data)
            dest = destdir / dest_file
            result = gen_scenario(args, data)
            with open(dest, "w+") as fd:
                json.dump(result, fd)


if __name__ == "__main__":
    main()
