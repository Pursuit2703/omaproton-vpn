#!/usr/bin/env python3
"""Print the signed-in account's own VPN tier as JSON: {"tier": 0}.

0 is Free, 2 is Plus, 3 is the internal PM tier. Used so servers.py can
prefer a city's free server over its best-scored one when the account
itself is Free — it can't use the best-scored one anyway, so showing it
is a dead end; a Plus account is unaffected and keeps seeing the
genuinely fastest server per city.

Reads it directly from the signed-in session via proton-vpn-cli's own
Controller, rather than parsing `protonvpn info`'s text output: that
output doesn't include a plan line on every CLI version (this account's
protonvpn 1.0.3 prints only "Account: '<email>'", nothing else), so
Model.parseAccount's `plan` field silently comes back empty here.
"""
import asyncio
import json
import sys

import click

from proton.vpn.cli.core.controller import Controller, Params


async def main():
    ctx = click.Context(click.Command("protonvpn"), info_name="protonvpn")
    controller = await Controller.create(Params(), ctx)
    if not controller.is_logged_in:
        print(json.dumps({"error": "not signed in"}))
        return 1
    print(json.dumps({"tier": int(controller.user_tier)}))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
