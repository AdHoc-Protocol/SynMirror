#!/usr/bin/ucode
// SYN Mirror: gives the server a port of meeting. It sends the password and its id, 8 random bytes of its own, to the first port
// of the range; the answer is a port of the others, 2 bytes, high first, given to that id: only knocks with it open the port, from
// whatever address. The rules of the kernel let only the right password through, a few a second from an address; the port is
// taken in the kernel - `nft create`, which fails when the port is taken already - so no two servers get one port, whatever else adds
// there. A server that asks again with the same id - its answer lost - gets the same port. The settings are those of /etc/config/syn-mirror; procd starts this again when they change.

import * as socket from 'socket';
import { cursor } from 'uci';
import { rand, srand } from 'math';

const main = cursor().get_all('syn-mirror', 'main') ?? {};
const password = main.password, first = +(main.first ?? 40000), last = +(main.last ?? 49999);

// a socket of the port of requests, at `address`; null when it cannot be bound. SO_REUSEADDR: the one of all the addresses and
// those of single ones share the port
function at(address) {
	const s = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
	if (s?.setopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, true) && s.bind({ address, port: first }))
		return s;
	s?.close();
	return null;
}

// An answer goes from the address its request came to: the kernel picks the address by the way back otherwise - a server in
// the LAN of the router, asking at its public address, would get the answer from its LAN address, and take none. The socket of
// all the addresses tells the address of each request it gets ( IP_PKTINFO ); the answer goes by a socket bound to that address,
// made at its first request, and the kernel brings the next requests to that address there: each socket answers from itself
const any = at('0.0.0.0');
if (!any) {
	warn(`syn-mirror: the port ${first}: ${socket.error()}\n`);
	exit(1);
}
any.setopt(socket.IPPROTO_IP, socket.IP_PKTINFO, true);
// the sockets of single addresses: [ socket, address ]
let single = [];

// the address a request came to, of its struct in_pktinfo: ipi_addr, its last 4 bytes
function asked(ancillary) {
	for (let c in ancillary ?? [])
		if (c.level == socket.IPPROTO_IP && c.type == socket.IP_PKTINFO && type(c.data) == 'string' && length(c.data) >= 12)
			return join('.', map(split(substr(c.data, 8, 4), ''), (b) => ord(b)));
	return null;
}

// the socket to answer by, from `address`: made when there is none yet; the socket of all the addresses when it cannot be bound
function by(address) {
	for (let s in single)
		if (s[1] == address)
			return s[0];
	const s = address ? at(address) : null;
	if (!s)
		return any;
	push(single, [ s, address ]);
	return s;
}
srand(time());

// the id of a request, in hex -> [ the port given, when ]: what a request again gets
let gave = {};

// a port of meeting nobody holds, given to `id`, 16 hex digits; null when 16 picks found none free
function give(id) {
	for (let i = 0; i < 16; i++) {
		const port = first + 1 + rand() % (last - first);
		if (system([ 'nft', `create element ip syn_mirror given { ${port} }; add element ip syn_mirror owned { ${port} . 0x${id} }` ]) == 0)
			return port;
	}
	return null;
}

// a request that came by `s`, to `address`: answered from there
function request(got, s) {
	// on a connection conntrack knows already the rules check no password: it is checked here
	const data = got?.data;
	if (length(data) != 16 || substr(data, 0, 8) !== password)
		return;
	const from = got.address, now = time(), id = join('', map(split(substr(data, 8), ''), (b) => sprintf('%02x', ord(b))));
	for (let k in keys(gave))
		if (now - gave[k][1] > 10)
			delete gave[k];
	const port = gave[id]?.[0] ?? give(id);
	if (port == null)
		return;
	gave[id] = [ port, now ];
	(s === any ? by(asked(got.ancillary)) : s).send(chr(port >> 8, port & 255), 0, from);
}

for (;;) {
	socket.poll(-1, [ any, socket.POLLIN ], ...map(single, (s) => [ s[0], socket.POLLIN ]));
	// every socket, what it has: without waiting
	for (let got; (got = any.recvmsg(64, 64, socket.MSG_DONTWAIT));)
		request(got, any);
	for (let s in single)
		for (let got; (got = s[0].recvmsg(64, 0, socket.MSG_DONTWAIT));)
			request(got, s[0]);
}
