#!/usr/bin/ucode
// SYN Mirror: gives the server a port of meeting. It sends the password, 16 characters, and its id, 8 random bytes of its own, to
// the first port of the range; the answer is a port of the others, 2 bytes, high first, given to that id: only knocks with it open
// the port, from whatever address. The rules of the kernel let only the right password through, a few a second from an address;
// the port is taken in the kernel - `nft create`, which fails when the port is taken already - so no two servers get one port,
// whatever else adds there. A server that asks again with an id that holds a port - its answer lost, or this router at another
// address now - gets that port. A fixed port is never given: it is its key's.
//
// The records, at the same port: a meeting point of a changing address writes its key and a port, 18 bytes, and the record keeps
// the address the write came from - the answer is that address, 4 bytes, as seen here; a read key, 16 bytes, gets the address, the
// port and the minutes since the last write, 7 bytes. And the reports: this router writes its own address into the records of
// other meeting points, every 20 s, and at once when its address changes. What the records and the reports hold is in
// /tmp/syn-mirror, for the page. The settings are those of /etc/config/syn-mirror; procd starts this again when they change.

import * as socket from 'socket';
import { cursor } from 'uci';
import { rand, srand } from 'math';
import { popen, readfile, writefile, rename, mkdir } from 'fs';

const ctx = cursor();
const main = ctx.get_all('syn-mirror', 'main') ?? {};
const password = main.password, first = +(main.first ?? 40000), last = +(main.last ?? 49999);
const STATE = '/tmp/syn-mirror';

// the fixed ports: never given at random
let fixed = {};
ctx.foreach('syn-mirror', 'fixed', (s) => { fixed[+s.port] = true; });

// the records: of each the address, the port, when written; by the write key and by each read key, its name
let records = {}, writers = {}, readers = {};
ctx.foreach('syn-mirror', 'record', (s) => {
	const name = s.name ?? s['.name'];
	records[name] = null;
	if (s.write)
		writers[s.write] = name;
	for (let k in (type(s.read) == 'array' ? s.read : split(s.read ?? '', ' ')))
		if (k)
			readers[k] = name;
});

// the reports: where this router writes its address. `to` is <write key>[/<read key>]@<host>:<port>
let reports = [];
ctx.foreach('syn-mirror', 'report', (s) => {
	const m = match(s.to ?? '', /^([A-Za-z0-9]{16})(\/[A-Za-z0-9]{16})?@([^ :@\/]+):([0-9]+)$/);
	if (!m) {
		warn(`syn-mirror: the report to '${s.to}': not <write key>[/<read key>]@<address>:<port>\n`);
		return;
	}
	const port = +(s.port || first);
	push(reports, { key: m[1], host: m[3], at: +m[4], write: m[1] + chr(port >> 8, port & 255),
		sock: null, local: null, tried: 0, sent: 0, answered: 0, seen: null });
});

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

// the 4 bytes of an IPv4 address
function bytes4(address) {
	return join('', map(split(address, '.'), (b) => chr(+b)));
}

// a file of /tmp/syn-mirror, whole: written beside, then put in place, so the page never reads half of it
function save(name, text) {
	mkdir(STATE);
	writefile(`${STATE}/${name}.new`, text);
	rename(`${STATE}/${name}.new`, `${STATE}/${name}`);
}

// the records as the page reads them: "<name> <address> <port> <when written>"
function saveRecords() {
	let text = '';
	for (let name, r in records)
		if (r)
			text += `${name} ${r.address} ${r.port} ${r.when}\n`;
	save('records', text);
}

// the reports as the page reads them: "<host>:<port> <port knocked at> <when sent> <when answered, 0 never> <address seen, or ->"
function saveReports() {
	let text = '';
	for (let r in reports)
		text += `${r.host}:${r.at} ${ord(r.write, 16) << 8 | ord(r.write, 17)} ${r.sent} ${r.answered} ${r.seen ?? '-'}\n`;
	save('reports', text);
}

// the records kept by the `give` before this one: a change of the settings starts it again, the records live on
for (let line in split(readfile(`${STATE}/records`) ?? '', '\n')) {
	const w = split(line, ' ');
	if (length(w) == 4 && exists(records, w[0]))
		records[w[0]] = { address: w[1], port: +w[2], when: +w[3] };
}

// the port of meeting the id holds, 16 hex digits, as the kernel has it; null - none
function held(id) {
	const p = popen('nft list set ip syn_mirror owned 2>/dev/null', 'r');
	const all = p?.read('all') ?? '';
	p?.close();
	// nft shows the id without the zeros in front
	const want = replace(id, /^0+/, '');
	for (let m in match(all, /([0-9]+) \. 0x([0-9a-f]+)/g))
		if (replace(m[2], /^0+/, '') == want)
			return +m[1];
	return null;
}

// a port of meeting nobody holds, given to `id`, 16 hex digits; null when 16 picks found none free
function give(id) {
	for (let i = 0; i < 16; i++) {
		const port = first + 1 + rand() % (last - first);
		if (fixed[port])
			continue;
		if (system([ 'nft', `create element ip syn_mirror given { ${port} }; add element ip syn_mirror owned { ${port} . 0x${id} }` ]) == 0)
			return port;
	}
	return null;
}

// a request that came by `s`, to `address`: answered from there
function request(got, s) {
	// on a connection conntrack knows already the rules check no key: it is checked here
	const data = got?.data, from = got?.address;
	let answer = null;
	if (length(data) == 24 && substr(data, 0, 16) === password) {
		// a port of meeting
		const id = join('', map(split(substr(data, 16), ''), (b) => sprintf('%02x', ord(b))));
		const port = held(id) ?? give(id);
		if (port != null)
			answer = chr(port >> 8, port & 255);
	} else if (length(data) == 18 && exists(writers, substr(data, 0, 16))) {
		// a write: the record takes the address it came from
		const name = writers[substr(data, 0, 16)];
		records[name] = { address: from.address, port: ord(data, 16) << 8 | ord(data, 17), when: time() };
		saveRecords();
		answer = bytes4(from.address);
	} else if (length(data) == 16 && exists(readers, data)) {
		// a read: the address, the port, the minutes since the last write - none while the record has none
		const r = records[readers[data]];
		const minutes = int((time() - r?.when) / 60);
		if (r)
			answer = bytes4(r.address) + chr(r.port >> 8, r.port & 255, minutes > 255 ? 255 : minutes);
	}
	if (answer != null)
		(s === any ? by(asked(got.ancillary)) : s).send(answer, 0, from);
}

// the address this router writes from to the meeting point of report `r`, as the kernel picks it now: a socket connected there,
// no packet sent; null - no way there now
function local(r) {
	const s = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
	const ok = r.addr && s?.connect(r.addr);
	const here = ok ? s.sockname()?.address : null;
	s?.close();
	return here;
}

// report `r` written: its name looked up anew when `look`, a new socket when the way there changed - another address of this
// router, or of that meeting point
function write(r, look) {
	r.tried = time();
	if (look || !r.addr) {
		const found = socket.addrinfo(r.host, `${r.at}`, { family: socket.AF_INET, socktype: socket.SOCK_DGRAM });
		if (found?.[0])
			r.addr = found[0].addr;
	}
	const here = local(r);
	if (!here)
		return;
	if (!r.sock || here != r.local || r.addr.address != r.to) {
		r.sock?.close();
		r.sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
		if (!r.sock?.connect(r.addr)) {
			r.sock?.close();
			r.sock = null;
			return;
		}
		r.local = here;
		r.to = r.addr.address;
	}
	r.sock.send(r.write);
	r.sent = time();
	saveReports();
}

for (let r in reports)
	write(r, true);
saveReports();
saveRecords();

for (;;) {
	let watched = [ [ any, socket.POLLIN ] ];
	for (let s in single)
		push(watched, [ s[0], socket.POLLIN ]);
	for (let r in reports)
		if (r.sock)
			push(watched, [ r.sock, socket.POLLIN ]);
	// woken each 2 s at most when there are reports: has the address changed, is one due
	socket.poll(length(reports) ? 2000 : -1, ...watched);
	// every socket, what it has: without waiting
	for (let got; (got = any.recvmsg(64, 64, socket.MSG_DONTWAIT));)
		request(got, any);
	for (let s in single)
		for (let got; (got = s[0].recvmsg(64, 0, socket.MSG_DONTWAIT));)
			request(got, s[0]);
	const now = time();
	for (let r in reports) {
		// the answer: the address this router wrote from, as that meeting point saw it
		for (let got; r.sock && (got = r.sock.recv(16, socket.MSG_DONTWAIT));)
			if (length(got) == 4) {
				r.answered = now;
				r.seen = join('.', map(split(got, ''), (b) => ord(b)));
				saveReports();
			}
		// each 20 s, its name looked up again; at once when this router writes from another address now - not while it has
		// no way there at all: the name is not looked up each 2 s then
		if (now - r.tried >= 20)
			write(r, true);
		else if (r.local) {
			const here = local(r);
			if (here && here != r.local)
				write(r, false);
		}
	}
}
