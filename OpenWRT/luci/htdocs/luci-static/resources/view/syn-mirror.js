'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require ui';
'require uci';
'require dom';

// The page of SYN Mirror: the meeting point for the server in one line, to copy - a line for the password, and one for each fixed
// port; what happens now - the meetings, the ports given to servers and what each is doing, the blocked addresses, the records
// of the meeting points of changing addresses and the reports of this router's own - the settings, the password first, and the
// removal of SYN Mirror from the router.

var callAddress = rpc.declare({ object: 'syn-mirror', method: 'address' });
var callStatus = rpc.declare({ object: 'syn-mirror', method: 'status' });
var callUninstall = rpc.declare({ object: 'syn-mirror', method: 'uninstall' });

// asks, then takes SYN Mirror off the router; the page goes to the overview of the router once it is gone
function uninstall() {
	ui.showModal(_('Uninstall SYN Mirror'), [
		E('p', _('The rules, the service, this page and the settings with the password are erased from the router. Connections that met end now.')),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
			E('button', { 'class': 'btn cbi-button-negative', 'click': function() {
				poll.stop();
				ui.showModal(_('Uninstall SYN Mirror'), [ E('p', { 'class': 'spinning' }, _('Erasing…')) ]);
				return callUninstall().then(function(r) {
					if (!r || !r.started)
						throw new Error(_('the script of removal is not on the router'));
					window.setTimeout(function() { window.location = L.url('admin/status/overview'); }, 5000);
				}).catch(function(e) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Not uninstalled: ') + e.message), 'error');
					poll.start();
				});
			} }, _('Uninstall'))
		])
	]);
}

// 16 letters and digits, those that are not mistaken for one another when read aloud or typed
function newPassword() {
	var abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789', bytes = new Uint8Array(16), out = '';
	window.crypto.getRandomValues(bytes);
	for (var i = 0; i < 16; i++)
		out += abc.charAt(bytes[i] % abc.length);
	return out;
}

// the clipboard of the browser: navigator.clipboard is there on https only, LuCI is mostly http
function copyText(text) {
	if (navigator.clipboard && window.isSecureContext)
		return navigator.clipboard.writeText(text).then(function() { return true; }, function() { return copyBySelection(text); });
	return Promise.resolve(copyBySelection(text));
}

function copyBySelection(text) {
	var t = E('textarea', { 'style': 'position:fixed; top:0; left:0; opacity:0' });
	t.value = text;
	document.body.appendChild(t);
	t.select();
	var ok = false;
	try { ok = document.execCommand('copy'); } catch (e) {}
	document.body.removeChild(t);
	return ok;
}

function bytesText(n) {
	if (n == null) return '-';
	var units = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
	while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
	return (i ? n.toFixed(1) : n) + ' ' + units[i];
}

// what a port given is doing: closed - its server waits for a yes of its person, or met a moment ago - open, or open and
// dialed
function portState(p) {
	if (p.state == 'dialing')
		return _('Open, the server dials from %s').format(p.dials);
	if (p.state == 'open')
		return _('Open, the server does not dial yet');
	return _('Closed, kept for the server');
}

// what a try of the last minutes was, in words
var tryWords = {
	'request': _('Asked for a port'),
	'knock': _('Knocked or held with the id the port is given to'),
	'stranger': _('Knocked, but not with the id the port is given to'),
	'wrong': _('Wrong password'),
	'blocked': _('Ignored: the address is blocked'),
	'guessing': _('Dialed, ignored: it guessed passwords at this port'),
	'dial-a': _('Dialed: the server of this port'),
	'dial': _('Dialed'),
	'wrote': _('Wrote its address'),
	'read': _('Read an address')
};

// a key of the settings: 16 letters or digits, and not the password
function keyValid(value) {
	if (!/^[A-Za-z0-9]{16}$/.test(value))
		return _('Exactly 16 letters or digits');
	return value != uci.get('syn-mirror', 'main', 'password') || _('Not the password: a key of its own');
}

// a setting of the section main, as the form holds it now, else as saved
function mainValue(map, name, otherwise) {
	var o = map.lookupOption(name, 'main');
	return (o ? o[0].formvalue('main') : null) || uci.get('syn-mirror', 'main', name) || otherwise;
}

// the line a report writes to: <key of writing>[/<key of reading>]@<meeting point>:<its port>; null - no such line
function parseTo(to) {
	var m = /^([A-Za-z0-9]{16})(?:\/([A-Za-z0-9]{16}))?@([^\s:@\/]+):(\d+)$/.exec(to || '');
	return m ? { write: m[1], read: m[2], host: m[3], port: m[4] } : null;
}

// each key of the settings, the password too, must be different, and each fixed port and each name of a record another: the
// words of the first one twice, or null
function twice() {
	var seen = {}, ports = {}, names = {}, found = null;
	function key(k, what) {
		if (!k || found) return;
		if (seen[k]) found = _('%s and %s have the same key: each key, and the password, must be different.').format(seen[k], what);
		else seen[k] = what;
	}
	key(uci.get('syn-mirror', 'main', 'password'), _('The password'));
	uci.sections('syn-mirror', 'fixed').forEach(function(s) {
		if (s.port && ports[s.port] && !found) found = _('The port %s is fixed twice.').format(s.port);
		ports[s.port] = true;
		key(s.key, _('The fixed port %s').format(s.port || '?'));
	});
	uci.sections('syn-mirror', 'record').forEach(function(s) {
		if (s.name && names[s.name] && !found) found = _('Two records are named %s.').format(s.name);
		names[s.name] = true;
		key(s.write, _('The key of writing of %s').format(s.name || '?'));
		L.toArray(s.read).forEach(function(k) { key(k, _('A key of reading of %s').format(s.name || '?')); });
	});
	return found;
}

function agoText(s) {
	return s < 60 ? _('%d s ago').format(s) : _('%d min %d s ago').format(Math.floor(s / 60), s % 60);
}

function table(head) {
	return E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, head.map(function(h) { return E('th', { 'class': 'th' }, h); }))
	]);
}

return view.extend({
	load: function() {
		// the settings: form.Map loads them itself
		return Promise.all([ L.resolveDefault(callStatus(), {}), L.resolveDefault(callAddress(), {}) ]);
	},

	// the address of this router for the lines: the name in DNS its owner set, else its public address - of its wan, or found by
	// STUN - else the one a meeting point it writes its address to saw last; null - none
	address: function() {
		var seen = (this.st.reports || []).filter(function(r) { return r.answered != null && r.seen; })
			.sort(function(a, b) { return a.answered - b.answered; })[0];
		return uci.get('syn-mirror', 'main', 'dns') || this.found.address || (seen ? seen.seen : null);
	},

	// the lines for the server, of the settings saved: the password's, <password>@<address>:<first port>, the port of requests
	// always, as nothing is to be guessed; then one of each fixed port, <key>=<address>:<port>. A port that reports write, with a
	// key of reading, into the records of meeting points: its line reads the address there, as this router's changes -
	// <password or key>@ or =<key of reading>@<meeting point>:<its port>, the reports in order. Each line: its id, its words, the
	// line, the line as shown - the password or key hidden - and a note; the line is null while something of it is missing
	lines: function() {
		var first = uci.get('syn-mirror', 'main', 'first') || '40000', address = this.address(), out = [];
		var reports = uci.sections('syn-mirror', 'report').map(function(s) {
			var r = parseTo(s.to);
			if (r) r.knock = s.port || first;
			return r;
		}).filter(function(r) { return r && r.read; });
		function line(id, label, secret, mark, port) {
			var via = reports.filter(function(r) { return +r.knock == +port; }),
			    where = via.length ? via.map(function(r) { return r.read + '@' + r.host + ':' + r.port; }).join(',') :
			            address ? address + ':' + port : null;
			out.push({
				id: id,
				label: label,
				text: secret && where ? secret + mark + where : null,
				shown: where ? '****************' + mark + where : '',
				note: !secret ? (id == 'main' ? _('Set a password below and save.') : _('Set its key below and save.')) :
					via.length ? _('The address of this router changes: the server reads it at %s, in this order.').format(via.map(function(r) { return r.host; }).join(', ')) :
					!where ? _('The public address of this router is not found: no server of STUN answered. Set its name in DNS below, in DNS name, or let it write its address to a meeting point, in Reports.') :
					''
			});
		}
		line('main', _('A port given at each start'), uci.get('syn-mirror', 'main', 'password'), '@', first);
		uci.sections('syn-mirror', 'fixed').forEach(function(s) {
			if (s.port)
				line(s['.name'], s.name ? _('The fixed port %s, %s').format(s.port, s.name) : _('The fixed port %s').format(s.port), s.key, '=', s.port);
		});
		return out;
	},

	// the lines as the page shows them, the password and the keys hidden, each with its button; made anew only when they change, so
	// that a button keeps what it says a moment
	showPoint: function() {
		var lines = this.lines(), texts = {}, sig = JSON.stringify(lines.map(function(l) { return [ l.id, l.label, l.shown, l.note, !!l.text ]; }));
		lines.forEach(function(l) { texts[l.id] = l.text; });
		this.texts = texts;
		if (sig !== this.sig) {
			this.sig = sig;
			dom.content(this.linesBox, lines.map(L.bind(function(l) {
				var button = { 'class': 'btn cbi-button-action', 'click': L.bind(this.copy, this, l.id) };
				if (!l.text) button.disabled = 'disabled';
				return E('div', { 'style': 'margin-bottom:1em' }, [
					E('strong', {}, l.label),
					E('p', {}, E('code', {}, l.shown)),
					l.note ? E('div', { 'class': 'cbi-section-descr' }, l.note) : '',
					E('button', button, _('Copy the meeting point'))
				]);
			}, this)));
		}
		this.lineNote.textContent = this.found.wan ? _('This router is behind another router or the NAT of its provider: its wan is %s. Forward the ports %s-%s, TCP and UDP, to it there.').format(this.found.wan,
			uci.get('syn-mirror', 'main', 'first') || '40000', uci.get('syn-mirror', 'main', 'last') || '49999') : '';
	},

	copy: function(id, ev) {
		var button = ev.currentTarget, text = this.texts[id];
		if (!text) return;
		return copyText(text).then(function(ok) {
			button.textContent = ok ? _('Copied') : _('Not copied: select the line and copy it');
			window.setTimeout(function() { button.textContent = _('Copy the meeting point'); }, 2000);
		});
	},

	// the line of a record for its meeting point, to paste into Reports there: <key of writing>/<key of reading>@<this router>:<first
	// port>, the first key of reading
	copyRecord: function(ev, section_id) {
		var button = ev.currentTarget, write = uci.get('syn-mirror', section_id, 'write'),
		    read = L.toArray(uci.get('syn-mirror', section_id, 'read'))[0], address = this.address();
		if (!write || !address) {
			ui.addNotification(null, E('p', !write ? _('Save the record first.') : _('The public address of this router is not found: set its name in DNS, in DNS name.')), 'warning');
			return;
		}
		return copyText(write + (read ? '/' + read : '') + '@' + address + ':' + (uci.get('syn-mirror', 'main', 'first') || '40000')).then(function(ok) {
			button.textContent = ok ? _('Copied') : _('Not copied');
			window.setTimeout(function() { button.textContent = _('Copy for the meeting point'); }, 2000);
		});
	},

	update: function(st) {
		this.st = st;
		this.showPoint();
		this.off.style.display = st.running ? 'none' : '';
		this.mute.style.display = st.running && !st.giving ? '' : 'none';
		cbi_update_table(this.meetings, (st.meetings || []).map(function(m) {
			return [ m.port, m.b, m.a, m.state, bytesText(m.bytes) ];
		}), E('em', _('No connections now')));
		var fixed = {};
		uci.sections('syn-mirror', 'fixed').forEach(function(s) { if (s.port) fixed[s.port] = s.name || ''; });
		cbi_update_table(this.ports, (st.ports || []).map(function(p) {
			var port = fixed[p.port] == null ? p.port : fixed[p.port] ? _('%d, fixed: %s').format(p.port, fixed[p.port]) : _('%d, fixed').format(p.port);
			return [ port, p.a || '-', portState(p), p.free ];
		}), E('em', _('No port is given')));
		this.recordsPart.style.display = uci.sections('syn-mirror', 'record').length ? '' : 'none';
		cbi_update_table(this.records, (st.records || []).map(function(r) {
			return [ r.name, r.address + ':' + r.port, agoText(r.ago) ];
		}), E('em', _('No meeting point wrote its address yet')));
		this.reportsPart.style.display = uci.sections('syn-mirror', 'report').length ? '' : 'none';
		cbi_update_table(this.reports, (st.reports || []).map(function(r) {
			return [ r.to, r.port, r.answered != null ? agoText(r.answered) : _('Never'), r.seen || '-' ];
		}), E('em', _('Nothing written yet')));
		cbi_update_table(this.blocked, (st.blocked || []).map(function(b) {
			return [ b.address, b.port ? _('Port %d: guessed passwords').format(b.port) : _('All: wrong passwords of SYN Mirror'), b.ends ];
		}), E('em', _('No address is blocked')));
		var tries = st.tries || [];
		this.triesNote.textContent = (st.tries_all > tries.length) ? _('The newest %d of %d.').format(tries.length, st.tries_all) : '';
		cbi_update_table(this.tries, tries.map(function(t) {
			return [ agoText(t.ago), t.from, t.port, tryWords[t.what] || t.what ];
		}), E('em', _('Nothing came in the last 10 minutes')));
	},

	render: function(data) {
		var st = data[0];
		// the public address of the router, and the address of its wan when that is not it
		this.found = data[1] || {};
		this.st = st;
		this.linesBox = E('div');
		this.lineNote = E('div', { 'class': 'cbi-section-descr' });
		var forA = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('For the server')),
			E('div', { 'class': 'cbi-section-descr' },
				_('This router as the meeting point, in one line: the password, @, the address, :, the port of requests - the server gets a port at each start. A fixed port has a line of its own: its key, =, the address, :, the port - the client connects to the same port every time. Paste the line where RemoteDesk asks for the meeting point, or give it to the script of the server, syn-mirror-server. The button copies it, the password or the key too.')),
			this.linesBox,
			this.lineNote
		]);

		this.off = E('div', { 'class': 'alert-message warning' },
			_('SYN Mirror is not running: set a password of 16 characters below and save.'));
		this.mute = E('div', { 'class': 'alert-message warning' },
			_('The service gives no ports now: servers get none. Restart it under System > Startup, syn-mirror.'));
		this.meetings = table([ _('Port'), _('Client (connected)'), _('Server (waited)'), _('State'), _('Data') ]);
		this.ports = table([ _('Port'), _('The server'), _('Now'), _('Free in, unless A knocks') ]);
		this.blocked = table([ _('Address'), _('Where, why'), _('Blocked for') ]);
		this.tries = table([ _('When'), _('From'), _('Port'), _('What') ]);
		this.triesNote = E('span');
		this.records = table([ _('Record'), _('Address and port'), _('Written') ]);
		this.recordsPart = E('div', {}, [
			E('h4', _('Records')),
			E('div', { 'class': 'cbi-section-descr' }, _('The addresses meeting points of changing addresses wrote here, and the port to knock at there: servers read them with a key of reading.')),
			this.records
		]);
		this.reports = table([ _('Written to'), _('Port'), _('Last answer'), _('This router, as it saw it') ]);
		this.reportsPart = E('div', {}, [
			E('h4', _('Reports')),
			E('div', { 'class': 'cbi-section-descr' }, _('The meeting points this router writes its address to: every 20 seconds, and at once when it changes.')),
			this.reports
		]);
		this.update(st);
		poll.add(L.bind(function() { return L.resolveDefault(callStatus(), {}).then(L.bind(this.update, this)); }, this), 5);

		var now = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('Now')),
			this.off,
			this.mute,
			E('h4', _('Connections')), this.meetings,
			E('h4', _('Ports given to servers')), this.ports,
			E('h4', _('Blocked addresses')),
			E('div', { 'class': 'cbi-section-descr' }, _('An address is blocked after too many requests or knocks with a wrong password; or, at one port, after too many short connections to it: guessing passwords.')),
			this.blocked,
			E('h4', _('Tries, the last 10 minutes')),
			E('div', { 'class': 'cbi-section-descr' }, [
				_('Requests for a port, knocks, addresses written and read, and SYNs to the ports given: from which address and port, to which port. The SYNs of the scanners of the internet, to ports nobody holds, are not shown. '),
				this.triesNote
			]),
			this.tries,
			this.recordsPart,
			this.reportsPart
		]);

		// the title and what happens now stand outside the form: saving renders the form anew, and with it whatever is inside
		var m = new form.Map('syn-mirror');
		var s = m.section(form.NamedSection, 'main', 'syn-mirror', _('Settings'));

		var o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.Value, 'password', _('Password'),
			_('16 letters or digits. The server asks for a port and knocks with it; after a change, give the new one to every server.'));
		o.password = true;
		o.rmempty = false;
		o.validate = function(id, value) {
			return /^[A-Za-z0-9]{16}$/.test(value) || _('Exactly 16 letters or digits');
		};

		o = s.option(form.Button, '_new', ' ');
		o.inputtitle = _('Make a new password');
		o.inputstyle = 'apply';
		o.onclick = function(ev, section_id) {
			var field = this.map.lookupOption('password', section_id)[0].getUIElement(section_id);
			field.setValue(newPassword());
			field.node.querySelector('input').type = 'text'; // the new one is shown, to be copied
		};

		o = s.option(form.Value, 'first', _('First port'), _('The server asks this port for a port of meeting, and gets a free one of the ports after it.'));
		o.datatype = 'port';
		o.placeholder = '40000';
		o = s.option(form.Value, 'last', _('Last port'), _('The last port of meeting. Open the whole range, TCP and UDP, to the internet.'));
		o.datatype = 'port';
		o.placeholder = '49999';
		o = s.option(form.Value, 'dns', _('DNS name'),
			_('Optional: a name of this router in DNS, when you keep one. The line above has it then, not the public address. Empty: the public address of the router.'));
		o.datatype = 'hostname';
		o.placeholder = this.found.address || '';
		o = s.option(form.Value, 'wait', _('Wait, seconds'), _('How long a port stays given to the server, and open, after the server stops knocking at it.'));
		o.datatype = 'uinteger';
		o.placeholder = '60';
		o = s.option(form.Value, 'tries', _('Wrong tries allowed'), _('Requests and knocks with a wrong password, per address. One more comes back each minute.'));
		o.datatype = 'range(1,1000)';
		o.placeholder = '5';
		o = s.option(form.Value, 'block', _('Block, seconds'), _('How long an address is blocked once its wrong tries run out: its requests and knocks are ignored, the right ones too. And how long an address that guessed at a port is kept from it.'));
		o.datatype = 'uinteger';
		o.placeholder = '600';
		o = s.option(form.Flag, 'guard', _('Guard against guessing'),
			_('Programs of the internet guess the passwords of Remote Desktop and SSH: each try is a short connection, refused in a second or two. An address with too many short connections to a port is blocked at that port. Off only for a server whose connections are short by nature.'));
		o.default = '1';
		o.rmempty = false;
		o = s.option(form.Value, 'short', _('Short, seconds'), _('A connection that ends within this time is short: a password tried and refused.'));
		o.datatype = 'range(1,3600)';
		o.placeholder = '20';
		o.depends('guard', '1');
		o = s.option(form.Value, 'guesses', _('Short connections allowed'), _('Per address and port. One more comes back each 10 minutes; past them the address is blocked at that port.'));
		o.datatype = 'range(1,1000)';
		o.placeholder = '5';
		o.depends('guard', '1');

		// a port of the range, after the first: the first answers the requests
		function inRange(value) {
			var first = +mainValue(m, 'first', '40000'), last = +mainValue(m, 'last', '49999');
			return (+value > first && +value <= last) || _('A port of %d-%d: of the range, after the first').format(first + 1, last);
		}

		s = m.section(form.TableSection, 'fixed', _('Fixed ports'),
			_('A port that stays the same: the server knocks at it with its key alone, nothing asked, and the client connects to the same port every time. Its line is above, in For the server. The port is never given to another server, nor opened without its key.'));
		s.anonymous = true;
		s.addremove = true;
		// a new one comes with a key of its own: kept by the save of the add, which takes away what no field shows yet but for
		// `retain`
		s.handleAdd = function(ev, name) {
			var id = this.map.data.add('syn-mirror', 'fixed', name);
			this.map.data.set('syn-mirror', id, 'key', newPassword());
			return this.map.save(null, true);
		};
		o = s.option(form.Value, 'name', _('Name'), _('Optional: what it is, for this page'));
		o.validate = function(id, value) {
			return /^[A-Za-z0-9_-]*$/.test(value) || _('Letters, digits, - and _');
		};
		o = s.option(form.Value, 'port', _('Port'));
		o.datatype = 'port';
		o.rmempty = false;
		o.validate = function(id, value) { return inRange(value); };
		o = s.option(form.Value, 'key', _('Key'), _('16 letters or digits: the server knocks with it'));
		o.password = true;
		o.rmempty = false;
		o.retain = true;
		o.validate = function(id, value) { return keyValid(value); };
		o = s.option(form.Button, '_new', ' ');
		o.inputtitle = _('New key');
		o.onclick = function(ev, section_id) {
			var field = this.map.lookupOption('key', section_id)[0].getUIElement(section_id);
			field.setValue(newPassword());
			field.node.querySelector('input').type = 'text';
		};

		s = m.section(form.TableSection, 'record', _('Records: addresses of meeting points that change'),
			_('For a meeting point whose public address changes: it writes its address here with the key of writing - every 20 seconds, and at once when it changes - and a server reads it with a key of reading, then meets there. Copy for the meeting point gives the line to paste on its page, in Reports.'));
		s.anonymous = true;
		s.addremove = true;
		// a new one comes with its keys, and a name to change: `retain` keeps them, as for a fixed port
		s.handleAdd = function(ev, name) {
			var id = this.map.data.add('syn-mirror', 'record', name);
			this.map.data.set('syn-mirror', id, 'name', 'point' + uci.sections('syn-mirror', 'record').length);
			this.map.data.set('syn-mirror', id, 'write', newPassword());
			this.map.data.set('syn-mirror', id, 'read', [ newPassword() ]);
			return this.map.save(null, true);
		};
		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o.retain = true;
		o.validate = function(id, value) {
			return /^[A-Za-z0-9_-]+$/.test(value) || _('Letters, digits, - and _');
		};
		o = s.option(form.Value, 'write', _('Key of writing'), _('Only the meeting point it is for writes with it'));
		o.password = true;
		o.rmempty = false;
		o.retain = true;
		o.validate = function(id, value) { return keyValid(value); };
		o = s.option(form.DynamicList, 'read', _('Keys of reading'), _('The servers read the address with one of them; one for each, to take back one by one'));
		o.retain = true;
		o.validate = function(id, value) {
			var bad = L.toArray(value).map(keyValid).filter(function(v) { return v !== true; })[0];
			return bad || true;
		};
		o = s.option(form.Button, '_copy', ' ');
		o.inputtitle = _('Copy for the meeting point');
		o.onclick = L.bind(this.copyRecord, this);

		s = m.section(form.TableSection, 'report', _('Reports: this router writes its address'),
			_('When the public address of this router changes: a meeting point of a fixed address keeps it for the servers. Paste the line its page copies for this router, under Records there. Port: the port the servers knock at, written with the address - empty for the port of requests, or a fixed port of this router. The lines For the server read the address there then.'));
		s.anonymous = true;
		s.addremove = true;
		o = s.option(form.Value, 'to', _('Meeting point'), _('The key of writing, /, the key of reading, @, its address, :, its port'));
		o.rmempty = false;
		o.validate = function(id, value) {
			return !!parseTo(value) || _('As its page copies it, such as Wk3vB9xQm2Lp7sRd/Rk8mP2qLx4Nc9TzE@203.0.113.7:40000');
		};
		o = s.option(form.Value, 'port', _('Port'), _('Empty: the port of requests'));
		o.datatype = 'port';
		o.validate = function(id, value) {
			return !value || value == mainValue(m, 'first', '40000') || inRange(value);
		};

		// keys twice are found here, across the sections: none is saved then. Saved, the lines for the server are those of the
		// settings now, at once
		var page = this;
		m.save = function(cb, silent) {
			return form.Map.prototype.save.call(this, function() {
				var found = twice();
				if (found)
					throw new Error(found);
				return cb ? cb() : null;
			}, silent).then(function(r) {
				page.update(page.st);
				return r;
			});
		};

		return m.render().then(L.bind(function(settings) {
			// uci has the settings now: form.Map loaded them - the lines, and which parts of Now there are
			this.update(this.st);
			return E('div', {}, [
				E('h2', _('SYN Mirror')),
				E('div', { 'class': 'cbi-map-descr' },
					_('Two computers behind NAT connect through this router: the server gets a free port with the password, opens it and waits, the client connects to that port. The router joins them, and passes their traffic like a forwarded port.')),
				forA,
				now,
				settings,
				E('div', { 'class': 'cbi-section' }, [
					E('h3', _('Uninstall')),
					E('div', { 'class': 'cbi-section-descr' },
						_('Takes SYN Mirror off this router completely, its settings too. To have it again, run the installer once more.')),
					E('button', { 'class': 'btn cbi-button-negative', 'click': uninstall }, _('Uninstall SYN Mirror'))
				])
			]);
		}, this));
	}
});
