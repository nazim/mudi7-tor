#!/bin/sh
# Restores GL.iNet's stock vpn-client handler and removes mudi7-tor.
# Tor, VPN, torrc and the exit country setting stay as they are.
set -eu

VPN_SHA=35d3538e296b76cc5a5c576bd818a2f0ad01d53c870c7bc693c4e5aa84b1e8c1
vpn=/usr/lib/oui-httpd/rpc/vpn-client
wg=/usr/lib/oui-httpd/rpc/wg-client
text=/etc/gl_screen/language/text/default
lib=/usr/lib/mudi7-tor

die() { printf 'mudi7-tor: %s\n' "$1" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die 'run as root on the router'
[ -f "$lib/vpn-client.original" ] || die "no backup in $lib; nothing to restore"
[ "$(sha256sum "$lib/vpn-client.original" | awk '{print $1}')" = "$VPN_SHA" ] ||
	die 'backup differs from the stock handler; not restoring'

if [ -x /etc/init.d/mudi7-tor-sig ]; then
	/etc/init.d/mudi7-tor-sig stop || :
	/etc/init.d/mudi7-tor-sig disable || :
	rm -f /etc/init.d/mudi7-tor-sig
fi
cp -p "$lib/vpn-client.original" "$vpn.restore"
mv "$vpn.restore" "$vpn"
if [ -e "$wg" ] && grep -q 'mudi7-tor' "$wg"; then rm -f "$wg"; fi
nginx -s reload
if [ -f "$lib/text.original" ]; then
	cp -p "$lib/text.original" "$text.restore"
	mv "$text.restore" "$text"
	/etc/init.d/gl_screen restart
fi
rm -rf "$lib" /usr/libexec/mudi7-tor /var/run/mudi7-tor
echo 'mudi7-tor: stock handlers restored.'
