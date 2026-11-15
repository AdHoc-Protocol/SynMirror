'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require ui';
'require uci';

// The page of SYN Mirror: the meeting point for the server in one line, to copy; what happens now - the meetings, the ports given to servers and
// what each is doing, the blocked addresses - the settings, the password first, and the removal of SYN Mirror from the router.

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

// 8 letters and digits, those that are not mistaken for one another when read aloud or typed
function newPassword() {
	var abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789', bytes = new Uint8Array(8), out = '';
	window.crypto.getRandomValues(bytes);
	for (var i = 0; i < 8; i++)
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
	'dial': _('Dialed')
};

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

	// the meeting point for the server in one line, of the settings saved: <password>@<address>:<first port>, the port of requests
	// always, as nothing is to be guessed. The address: the name in DNS its owner set, else the public address of the router; null
	// while there is no address or no password
	point: function(password) {
		var address = uci.get('syn-mirror', 'main', 'dns') || this.found.address,
		    first = uci.get('syn-mirror', 'main', 'first') || '40000';
		password = password || uci.get('syn-mirror', 'main', 'password');
		if (!address || !password) return null;
		return password + '@' + address + ':' + first;
	},

	// the line as the page shows it, the password hidden; what is missing in it, or to be done for it, below
	showPoint: function() {
		var shown = this.point('********'), dns = uci.get('syn-mirror', 'main', 'dns');
		this.line.textContent = shown || '';
		this.copyButton.disabled = !shown;
		this.lineNote.textContent =
			!dns && !this.found.address ? _('The public address of this router is not found: no server of STUN answered. Set its name in DNS below, in DNS name.') :
			!uci.get('syn-mirror', 'main', 'password') ? _('Set a password below and save.') :
			this.found.wan ? _('This router is behind another router or the NAT of its provider: its wan is %s. Forward the ports %s-%s, TCP and UDP, to it there.').format(this.found.wan,
				uci.get('syn-mirror', 'main', 'first') || '40000', uci.get('syn-mirror', 'main', 'last') || '49999') :
			'';
	},

	copy: function(ev) {
		var button = ev.currentTarget, text = this.point();
		if (!text) return;
		return copyText(text).then(function(ok) {
			button.textContent = ok ? _('Copied') : _('Not copied: select the line and copy it');
			window.setTimeout(function() { button.textContent = _('Copy the meeting point'); }, 2000);
		});
	},

	update: function(st) {
		this.showPoint();
		this.off.style.display = st.running ? 'none' : '';
		this.mute.style.display = st.running && !st.giving ? '' : 'none';
		cbi_update_table(this.meetings, (st.meetings || []).map(function(m) {
			return [ m.port, m.b, m.a, m.state, bytesText(m.bytes) ];
		}), E('em', _('No connections now')));
		cbi_update_table(this.ports, (st.ports || []).map(function(p) {
			return [ p.port, p.a || '-', portState(p), p.free ];
		}), E('em', _('No port is given')));
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
		this.line = E('code');
		this.lineNote = E('div', { 'class': 'cbi-section-descr' });
		this.copyButton = E('button', { 'class': 'btn cbi-button-action', 'click': L.bind(this.copy, this) }, _('Copy the meeting point'));
		var forA = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('For the server')),
			E('div', { 'class': 'cbi-section-descr' },
				_('This router as the meeting point, in one line: the password, @, the address, :, the port of requests. Paste it where RemoteDesk asks for the meeting point, or give it to rdp-host --meet. The button copies it, the password too.')),
			E('p', {}, this.line),
			this.lineNote,
			this.copyButton
		]);

		this.off = E('div', { 'class': 'alert-message warning' },
			_('SYN Mirror is not running: set a password of 8 characters below and save.'));
		this.mute = E('div', { 'class': 'alert-message warning' },
			_('The service gives no ports now: servers get none. Restart it under System > Startup, syn-mirror.'));
		this.meetings = table([ _('Port'), _('Client (connected)'), _('Server (waited)'), _('State'), _('Data') ]);
		this.ports = table([ _('Port'), _('The server'), _('Now'), _('Free in, unless A knocks') ]);
		this.blocked = table([ _('Address'), _('Where, why'), _('Blocked for') ]);
		this.tries = table([ _('When'), _('From'), _('Port'), _('What') ]);
		this.triesNote = E('span');
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
				_('Requests for a port, knocks, and SYNs to the ports given: from which address and port, to which port. The SYNs of the scanners of the internet, to ports nobody holds, are not shown. '),
				this.triesNote
			]),
			this.tries
		]);

		// the title and what happens now stand outside the form: saving renders the form anew, and with it whatever is inside
		var m = new form.Map('syn-mirror');
		var s = m.section(form.NamedSection, 'main', 'syn-mirror', _('Settings'));

		var o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.Value, 'password', _('Password'),
			_('8 letters or digits. The server asks for a port and knocks with it; after a change, give the new one to every server.'));
		o.password = true;
		o.rmempty = false;
		o.validate = function(id, value) {
			return /^[A-Za-z0-9]{8}$/.test(value) || _('Exactly 8 letters or digits');
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

		return m.render().then(L.bind(function(settings) {
			// uci has the settings now: form.Map loaded them
			this.showPoint();
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
