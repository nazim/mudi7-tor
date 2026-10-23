#!/bin/sh
# Run as root on the router from a staged copy of router/:
#   sh /tmp/mudi7-tor/install.sh
# Changes nothing unless firmware, model and every GL.iNet file this tool
# relies on match the inspected build, and restores the stock handlers if
# activation fails.
set -eu
umask 022

VPN_SHA=35d3538e296b76cc5a5c576bd818a2f0ad01d53c870c7bc693c4e5aa84b1e8c1
TOR_SHA=03e0166b1ec1329dde0d22f705c6589b764fcc69e68ab794ffbb185c90f3ffb8
WG_SO_SHA=2479c49271ddd97ced18e24613d822d2038521baebfc78f2914528e6324bc12c
LOADER_SHA=aa159dd603cb0ba1bf4f4b2efefa608133c9ec06e75709df2e0b3308554148b2
TEXT_SHA=12c5eff7edafb3c9b7bd60ffa69f9763682c0e2b1d06c1e8935f0c52799d2a11
text=/etc/gl_screen/language/text/default
rpcdir=/usr/lib/oui-httpd/rpc
vpn=$rpcdir/vpn-client
wg=$rpcdir/wg-client
lib=/usr/lib/mudi7-tor
bin=/usr/libexec/mudi7-tor
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

die() { printf 'mudi7-tor: %s\n' "$1" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[ "$(id -u)" = 0 ] || die 'run as root on the router'
[ "$(cat /etc/glversion)" = 4.10.0 ] || die 'only GL firmware 4.10.0 is supported'
[ "$(cat /proc/gl-hw-info/model)" = e5800 ] || die 'only the Mudi 7 (GL-E5800) is supported'
[ "$(sha $rpcdir/tor)" = "$TOR_SHA" ] || die 'GL tor handler differs from the inspected build'
[ "$(sha $rpcdir/wg-client.so)" = "$WG_SO_SHA" ] || die 'GL wg-client module differs from the inspected build'
[ "$(sha /usr/lib/lua/oui/rpc.lua)" = "$LOADER_SHA" ] || die 'GL RPC loader differs from the inspected build'
for c in lua jsonfilter curl nginx sha256sum; do
	command -v "$c" >/dev/null || die "missing command: $c"
done
# obfs4proxy is a plug-in, not part of the firmware; bridges need it.
if grep -q '^Bridge obfs4' /etc/tor/torrc 2>/dev/null && [ ! -x /usr/bin/obfs4proxy ]; then
	echo 'mudi7-tor: warning: torrc lists obfs4 bridges but obfs4proxy is not installed (Plug-ins)' >&2
fi

if [ -e "$lib/vpn-client.original" ]; then
	[ "$(sha "$lib/vpn-client.original")" = "$VPN_SHA" ] || die 'existing backup differs from the stock handler'
	echo 'mudi7-tor: reinstalling over a verified stock backup'
else
	[ "$(sha "$vpn")" = "$VPN_SHA" ] || die 'GL vpn-client handler differs from the inspected build'
fi
if [ -e "$lib/text.original" ]; then
	[ "$(sha "$lib/text.original")" = "$TEXT_SHA" ] || die 'existing text backup differs from the stock file'
else
	[ "$(sha "$text")" = "$TEXT_SHA" ] || die 'GL screen text file differs from the inspected build'
fi
# GL ships no Lua wg-client handler; only ours may be replaced.
if [ -e "$wg" ] && ! grep -q 'mudi7-tor' "$wg"; then
	die "$wg exists and is not from mudi7-tor"
fi

for f in tor-card.lua tor-lists.lua tor-state.lua filecache.lua vpn-client-wrapper.lua wg-client.lua lockscreen.lua tor-sig.lua; do
	lua - "$src/$f" <<'LUA' || die "syntax error in $f"
assert(loadfile(arg[1]))
LUA
done

mkdir -p "$lib" "$bin"
[ -e "$lib/vpn-client.original" ] || cp -p "$vpn" "$lib/vpn-client.original"
for f in tor-card.lua tor-lists.lua tor-state.lua filecache.lua lockscreen.lua rollback.sh; do
	cp "$src/$f" "$lib/$f"
done
cp "$src/switch" "$bin/switch"
cp "$src/tor-sig.lua" "$bin/tor-sig.lua"
chmod 755 "$bin/switch" "$lib/rollback.sh"

# Load the wrapper outside nginx first, posing as the touchscreen: it must
# list the stock tunnels plus exactly one Tor card before going live.
lua - "$src/vpn-client-wrapper.lua" <<'LUA'
ngx = {var = {remote_addr = '127.0.0.1'}, req = {get_headers = function() return {glinet = '1'} end}}
local w = assert(loadfile(arg[1]))()
local n = 0
for _, t in ipairs(w.get_tunnel({}).tunnels) do
    if t.tunnel_id == 919101 then n = n + 1 end
end
assert(n == 1, 'Tor card missing from get_tunnel')
LUA

activated=0
restore() {
	if [ "$activated" = 1 ]; then
		cp -p "$lib/vpn-client.original" "$vpn.restore"
		mv "$vpn.restore" "$vpn"
		rm -f "$wg"
		nginx -s reload
		echo 'mudi7-tor: activation failed, stock handlers restored' >&2
	fi
}
trap restore EXIT

cp "$src/vpn-client-wrapper.lua" "$vpn.new"
cp "$src/wg-client.lua" "$wg.new"
chmod 644 "$vpn.new" "$wg.new"
activated=1
mv "$vpn.new" "$vpn"
mv "$wg.new" "$wg"
nginx -s reload
sleep 2

port=$(grep -E '    listen [0-9]+;' /etc/nginx/conf.d/gl.conf | grep -oE '[0-9]+' | head -1)
call() {
	curl -s -m 20 -H 'glinet: 1' "http://127.0.0.1:${port:-80}/rpc" \
		-d "{\"jsonrpc\":\"2.0\",\"method\":\"call\",\"params\":[\"\",\"$1\",\"$2\",$3],\"id\":1}"
}
call vpn-client get_tunnel '{}' | jsonfilter -e '@.result.tunnels[@.tunnel_id=919101].name' |
	grep -qx Tor || die 'live vpn-client did not return the Tor card'
call wg-client get_group_list '{}' | jsonfilter -e '@.result.groups[@.group_id=919102].group_name' |
	grep -qx 'Tor' || die 'live wg-client did not return the Tor list'
[ "$(call wg-client get_config_list '{"group_id":919102}' | jsonfilter -e '@.result.peers[*].peer_id' | wc -l)" -gt 0 ] ||
	die 'live wg-client returned an empty Tor list'

activated=2

# Home screen VPN card labels. gl_screen reads screen text only from this
# file (the uci "cover" files feed a different key store), so the file
# itself is rewritten from the stock backup: exactly two lines change.
[ -e "$lib/text.original" ] || cp -p "$text" "$lib/text.original"
sed -e 's/^HOME_VPN_CARD_ON_LABEL_TEXT "VPN On"$/HOME_VPN_CARD_ON_LABEL_TEXT "VPN \/ TOR On"/' \
	-e 's/^HOME_VPN_CARD_OFF_LABEL_TEXT "VPN"$/HOME_VPN_CARD_OFF_LABEL_TEXT "VPN \/ TOR"/' \
	"$lib/text.original" > "$text.mudi7-tor"
changed=$(awk 'NR == FNR { a[FNR] = $0; next } a[FNR] != $0 { n++ } END { print n + 0 }' \
	"$lib/text.original" "$text.mudi7-tor")
if [ "$changed" != 2 ]; then
	rm -f "$text.mudi7-tor"
	die "expected 2 changed text lines, got $changed; Tor card stays installed, labels unchanged"
fi
if cmp -s "$text" "$text.mudi7-tor"; then
	rm -f "$text.mudi7-tor"
else
	chmod 644 "$text.mudi7-tor"
	mv "$text.mudi7-tor" "$text"
	# gl_screen loads text once at start; procd respawns it.
	/etc/init.d/gl_screen restart
fi

# Lock-screen Tor status. Its stop step restores the user's signature.
cp "$src/tor-sig.init" /etc/init.d/mudi7-tor-sig
chmod 755 /etc/init.d/mudi7-tor-sig
/etc/init.d/mudi7-tor-sig enable
/etc/init.d/mudi7-tor-sig restart

echo 'mudi7-tor: installed. Open VPN Dashboard on the touchscreen.'
