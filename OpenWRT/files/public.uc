#!/usr/bin/ucode
// The address the internet sees this router at, for the line the page copies for the server, when the address of its wan is not
// it: a NAT of the provider or another router in front. One STUN Binding request ( RFC 5389 ) to each public server below, from
// one socket; the first answer is printed. Nothing is printed when none answers in 2 seconds.

import * as socket from 'socket';
import { readfile } from 'fs';

// those of RemoteDesk: not each is reached from everywhere - Google is closed in mainland China, a server in China may be slow
// abroad - so all are asked at once
const servers = [
	'stun.miwifi.com:3478', 'stun.chat.bilibili.com:3478', 'stun.hitv.com:3478', 'stun.douyucdn.cn:18000', 'stun.qq.com:3478',
	'stun.l.google.com:19302', 'stun.cloudflare.com:3478', 'global.stun.twilio.com:3478', 'stun.nextcloud.com:3478',
	'stun.sipgate.net:3478', 'stun.kinesisvideo.ap-east-1.amazonaws.com:443'
];
const COOKIE = '\x21\x12\xa4\x42';

const udp = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
const id = readfile('/dev/urandom', 12);
// Binding, no attributes, the cookie, the id of this request
const request = '\x00\x01\x00\x00' + COOKIE + id;

// the address of an attribute XOR-MAPPED-ADDRESS ( its bytes xor the cookie ) or MAPPED-ADDRESS, IPv4; null else
function mapped(answer, at, xor) {
	if (ord(answer, at + 1) != 1)
		return null;
	let bytes = [];
	for (let i = 0; i < 4; i++)
		push(bytes, xor ? ord(answer, at + 4 + i) ^ ord(COOKIE, i) : ord(answer, at + 4 + i));
	return join('.', bytes);
}

// the answer to this request: a Binding success with the same cookie and id
function address(answer) {
	if (length(answer) < 20 || substr(answer, 0, 2) != '\x01\x01' || substr(answer, 4, 16) != COOKIE + id)
		return null;
	let plain = null;
	for (let at = 20; at + 4 <= length(answer);) {
		const type = ord(answer, at) << 8 | ord(answer, at + 1), size = ord(answer, at + 2) << 8 | ord(answer, at + 3);
		if (type == 0x0020)
			return mapped(answer, at + 4, true);
		if (type == 0x0001)
			plain = mapped(answer, at + 4, false);
		at += 4 + ((size + 3) & ~3);
	}
	return plain;
}

// the answers that came within `ms` milliseconds: the first right one is printed, and that is all
function answered(ms) {
	while (socket.poll(ms, [ udp, socket.POLLIN ])?.[0]?.[1] & socket.POLLIN) {
		const found = address(udp.recv(512));
		if (found) {
			print(found, '\n');
			exit(0);
		}
	}
}

// the names are looked up one by one: an answer that came meanwhile ends it at once, without the lookups left
for (let s in servers) {
	const at = split(s, ':');
	const found = socket.addrinfo(at[0], at[1], { family: socket.AF_INET, socktype: socket.SOCK_DGRAM });
	if (found?.[0])
		udp.send(request, 0, found[0].addr);
	answered(0);
}
const until = time() + 2;
for (let left = 2000; left > 0; left = (until - time()) * 1000)
	answered(left);
exit(1);
