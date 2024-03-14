#!python

import argparse as ap
import json
import re
from pathlib import Path

SCENARIO_PATTERN = r"scenario_dump_cpp_protobuf_(?P<api>sync|async)_(?P<mode>streaming|unary)_qps_unconstrained_(?P<tls>secure|insecure)_(?P<size>[0-9]+)b"

# Generate the scenario variants with a fixed message limit that replaces the time limit.
def patch_scenario(args, data):
    for scenario in data["scenarios"]:
        if "benchmark_seconds" in scenario:
            del scenario["benchmark_seconds"]
        scenario["warmup_seconds"] = args.w

        client_conf = scenario["client_config"]
        if args.a == "time":
            scenario["benchmark_seconds"] = args.t
        else:
            is_unary = client_conf["rpc_type"] == "UNARY"
            if is_unary:
                scenario["message_limit"] = args.u
            else:
                scenario["message_limit"] = args.s
    return data


def gen_filename(args, data, limit_suffix):
    scenario = data["scenarios"][0]
    client_conf = scenario["client_config"]

    if client_conf["client_type"] == "ASYNC_CLIENT":
        client_type = "async"
    else:
        client_type = "sync"
    if client_conf["rpc_type"] == "UNARY":
        rpc_type = "unary"
    else:
        rpc_type = "streaming"
    if client_conf["security_params"] is not None:
        tls = "secure"
    else:
        tls = "insecure"
    size = client_conf["payload_config"]["simple_params"]["req_size"]

    return f"qps_{client_type}_{rpc_type}_{tls}_{size}b_{limit_suffix}.json"


def gen_filename_msglimit(args, data):
    client_conf = data["scenarios"][0]["client_config"]
    if client_conf["rpc_type"] == "UNARY":
        limit = str(args.u)
    else:
        limit = str(args.s)

    nzeros = len(limit) - len(limit.rstrip("0"))
    if nzeros >= 9:
        limit = limit[:-9] + "G"
    elif nzeros >= 6:
        limit = limit[:-6] + "M"
    elif nzeros >= 3:
        limit = limit[:-3] + "K"

    return gen_filename(args, data, limit)


def gen_filename_timelimit(args, data):
    limit_suffix = str(args.t) + "s"

    return gen_filename(args, data, limit_suffix)


def gen_scenario(destdir, name, args):
    print(f"Generate {args.a}-limited scenario based on {name.stem}")
    with open(name, "r") as fd:
        data = json.load(fd)

        if args.a == "time":
            dest_file = gen_filename_timelimit(args, data)
        else:
            dest_file = gen_filename_msglimit(args, data)
        dest = destdir / dest_file

        result = patch_scenario(args, data)
        with open(dest, "w+") as fd:
            json.dump(result, fd)

def gen_timelimit_scenario(name, args, data):
    print("Generate TIME-limited scenario based on", name.stem)
    with open(name, "r") as fd:
        data = json.load(fd)
        dest_file = gen_filename(args, data)
        dest = destdir / dest_file
        result = gen_scenario(args, data)
        with open(dest, "w+") as fd:
            json.dump(result, fd)

def main():
    parser = ap.ArgumentParser("Scenario editor")
    parser.add_argument("-u", type=int, help="Unary message limit", default=200000)
    parser.add_argument("-s", type=int, help="Streaming message limit", default=200000)
    parser.add_argument("-t", type=int, help="Set time limit (seconds)", default=30)
    parser.add_argument("-w", type=int, help="Set the warmup period", default=5)
    parser.add_argument("-c", action="store_true", help="Clear the generated scenarios")
    parser.add_argument("-a", choices=["time", "msg"], default=None)

    args = parser.parse_args()
    curdir = Path.cwd()
    destdir = curdir / "gen"
    destdir.mkdir(exist_ok=True)

    if args.c:
        for name in destdir.iterdir():
            name.unlink()
        return

    if args.a is None:
        print("Missing -a argument")
        exit(1)

    for name in curdir.iterdir():
        m = re.match(SCENARIO_PATTERN, name.stem)
        if m:
            gen_scenario(destdir, name, args)


if __name__ == "__main__":
    main()
