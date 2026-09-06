#!/usr/bin/env python3
"""Connect to a specific country, city, or named server on a Free account.

`protonvpn connect --country/--city/<NAME>` (proton.vpn.cli.core.controller.
Controller.find_logical_server) blanket-refuses every one of those on a Free
account, before it ever reaches the real per-server check a few lines later:

    free_user = self.user_tier == 0
    requesting_paying_feature = (server_name or country or city or ...)
    if free_user and requesting_paying_feature:
        raise RequiresHigherTierError               # <- always fires first
    ...
    servers = ServerList.get_available_servers(servers, self.user_tier)  # <- the real, per-server check

That second line is the actual entitlement check: LogicalServer.tier's own
docstring says "Server-side check is always done, so this is mainly for UI
purposes." The blanket check above it just stops the CLI from *trying* a
location a Free account may well have servers in — exactly the Free-tagged
cities servers.py already lists in the panel, which otherwise fail with
"Requires a Proton VPN Plus plan" despite being real, connectable, free
servers.

This monkeypatches out only that blanket check, for the plain "country/city/
named server" case (server_name, country, or city; never --random or a
feature flag) on a Free account. Every other case — Plus accounts, --random,
--p2p/--securecore/--tor, or a paid-only target — runs the original,
unmodified method, so this can never select or connect to a server the
account isn't entitled to; it only stops the CLI refusing to try one it is.

A version guard refuses to patch (falling back to the stock, restricted
behavior) if Controller doesn't look like the shape this was written
against, so a proton-vpn-cli update can't leave this silently wrong.

Usage: connect_location.py --country NL
       connect_location.py --city Amsterdam
       connect_location.py NL-FREE#42
"""
import sys


def _bail(message):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


try:
    from proton.vpn.cli.core import controller as controller_module
except ImportError as exc:
    _bail(f"proton-vpn-cli internals not importable ({exc})")

if not (hasattr(controller_module, "Controller")
        and hasattr(controller_module.Controller, "find_logical_server")
        and hasattr(controller_module.Controller, "validate_country_input")):
    _bail("proton-vpn-cli's Controller doesn't match the shape this was written against — refusing to patch.")

from proton.vpn.session.exceptions import ServerNotFoundError  # noqa: E402

_original_find_logical_server = controller_module.Controller.find_logical_server


async def _patched_find_logical_server(self, server_name=None, country=None, city=None, features=0, random_server=False):
    free_user = self.user_tier == 0
    plain_location_request = bool(server_name or country or city) and not features and not random_server

    if not (free_user and plain_location_request):
        return await _original_find_logical_server(self, server_name, country, city, features, random_server)

    from proton.vpn.cli.core.exceptions import AuthenticationRequiredError
    if not self._api.is_user_logged_in():  # pylint: disable=protected-access
        raise AuthenticationRequiredError

    server_list = await self.get_updated_server_list()

    if server_name:
        # get_by_name is unfiltered by tier, so check .free ourselves — a
        # paid-only name resolves to "not found", never a connect attempt.
        server = server_list.get_by_name(server_name)
        return server if (server and server.free) else None

    try:
        if city:
            return server_list.get_fastest_in_city(city)
        return server_list.get_fastest_in_country(self.validate_country_input(country))
    except ServerNotFoundError:
        return None


controller_module.Controller.find_logical_server = _patched_find_logical_server

from proton.vpn.cli import main  # noqa: E402  (import after the patch is applied)

if __name__ == "__main__":
    sys.argv = [sys.argv[0], "connect"] + sys.argv[1:]
    sys.exit(main())
