// Draws the pictures of the README into docs/: `npm install`, then `node draw.mjs`, here.
//
// By hand ( Rough.js ), in the hand of Coming Soon ( Apache License 2.0, inside each picture ) and the colours of the pictures of
// RemoteDesk, light or dark as the screen of the reader is. The server is blue, the client green, the meeting point amber. Each
// picture is one SVG that moves by itself: the pulses, the steps lit in turn are animations of CSS and of SVG, no script - GitHub
// shows them so.

import { readFileSync, writeFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import rough from "roughjs";

const document = new JSDOM("<!doctype html><html><body></body></html>").window.document;
const NS = "http://www.w3.org/2000/svg";
const HAND = "data:font/woff2;base64,"
    + readFileSync(new URL("node_modules/@fontsource/coming-soon/files/coming-soon-latin-400-normal.woff2", import.meta.url)).toString("base64");

/** The style of every picture: the paper, the pen, the hand; the colours of A, B and the meeting point. */
const STYLE = `
@font-face { font-family: "SM Hand"; src: url(${HAND}) format("woff2"); }
:root { --ink: #3a3f4a; --paper: #fffdf8; --soft: #eceff4; --line: #cfd5de; --dot: #e3e1da; --hatch: #b9cbe3; --muted: #5b6475;
        --a: #2f6fde; --b: #2b8a4b; --meet: #b26b00; --bad: #c4352b; }
@media (prefers-color-scheme: dark) { :root { --ink: #c9d0dc; --paper: #171b22; --soft: #222833; --line: #343b47; --dot: #262c36;
        --hatch: #3c5576; --muted: #98a0ae; --a: #6b9bf2; --b: #5cc27e; --meet: #e0a84a; --bad: #ef6a5f; } }
.hand { font-family: "SM Hand", "Segoe Print", "Bradley Hand", cursive; fill: var(--pen, var(--ink)); }
.hand.small { fill: var(--muted); }
.mono { font: 15px ui-monospace, Consolas, monospace; fill: var(--ink); }
.screen-text { fill: var(--pen, var(--a)); }
.o path { stroke: var(--pen, var(--ink)); }
.card path[fill]:not([fill=none]) { fill: var(--paper); }
.screen path:not(:last-child), .cloud path:not(:last-child) { stroke: var(--hatch); }
.box path[fill]:not([fill=none]), .deck path[fill]:not([fill=none]) { fill: var(--soft); }
.deck path:not(:last-child) { stroke: var(--line); }
.console path[fill]:not([fill=none]) { fill: #20242c; }
.head path[fill]:not([fill=none]) { fill: var(--pen, var(--ink)); }
.life path { stroke: var(--line); }
.console-text { font: 13px ui-monospace, Consolas, monospace; fill: #9fe3a8; }
.console-text.strong { fill: #fff; font-weight: 700; }
.cursor { fill: #9fe3a8; animation: blink 1s steps(1) infinite; }
.pip { fill: var(--ink); opacity: .5; }
.led { fill: var(--b); opacity: .5; }
.alive .led { animation: blink .5s steps(1) infinite; opacity: 1; }
.led-1 { animation-delay: .17s !important; } .led-2 { animation-delay: .33s !important; }
.dot { fill: var(--pen, var(--b)); filter: url(#glow); }
@keyframes blink { 50% { opacity: .15; } }
`;

const el = (tag, attrs = {}, parent, text) => {
    const e = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
    if (text !== undefined) e.textContent = text;
    parent?.append(e);
    return e;
};

/** Words written by hand: the hand is big for its size, so it is drawn smaller than asked. */
const write = (parent, x, y, text, size = 22, cls = "", anchor = "middle") =>
    el("text", { x, y, "font-size": size * 0.8, "text-anchor": anchor, class: ("hand " + cls).trim() }, parent, text);

/** The pen: how Rough.js draws; its colour is the style's, `--pen` of the part it is in. */
const PEN = { roughness: 1.3, bowing: 1.1, strokeWidth: 2.2, stroke: "#333" };

/** An outline by hand, put in `g`. */
function outline(g, shape, cls = "o") {
    shape.classList.add(...cls.split(" "));
    g.append(shape);
    return shape;
}

/** A part in the colour of its owner. */
const part = (parent, pen, attrs = {}) => el("g", { ...attrs, style: `--pen: var(${pen})` }, parent);

/** Pulses running along the path `id`: `n` each way, `back` - the other way too. */
function pulses(parent, id, n, seconds, back) {
    for (const reverse of back ? [false, true] : [false]) for (let i = 0; i < n; i++) {
        const dot = el("circle", { r: 5, class: "dot" }, parent);
        const motion = el("animateMotion", { dur: `${seconds}s`, begin: `${(-seconds * i) / n - (reverse ? seconds / (2 * n) : 0)}s`, repeatCount: "indefinite" }, dot);
        if (reverse) { motion.setAttribute("keyPoints", "1;0"); motion.setAttribute("keyTimes", "0;1"); motion.setAttribute("calcMode", "linear"); }
        el("mpath", { href: "#" + id }, motion);
    }
}

/** The cloud of the internet around (`cx`, `cy`), `w` × `h`: bumps all around. */
function cloudPath(cx, cy, w, h) {
    const bumps = [[-0.42, 0.18, 0.22], [-0.3, -0.12, 0.26], [-0.08, -0.32, 0.3], [0.2, -0.26, 0.27], [0.4, -0.02, 0.22], [0.33, 0.24, 0.2],
        [0.08, 0.32, 0.22], [-0.2, 0.32, 0.22]];
    const pts = bumps.map(([x, y, r]) => [cx + x * w, cy + y * h, r * Math.min(w, h * 1.4)]);
    let d = "";
    pts.forEach(([x, y, r], i) => {
        const [nx, ny] = pts[(i + 1) % pts.length];
        if (i === 0) d += `M ${x} ${y + r * 0.6} `;
        d += `Q ${(x + nx) / 2 + (x + nx - 2 * cx) * 0.35} ${(y + ny) / 2 + (y + ny - 2 * cy) * 0.55} ${nx} ${ny + r * 0.1} `;
    });
    return d + "Z";
}

/** A laptop ( x 24…292, y 146…298 ): `screen` written on it. */
function laptop(rc, g, screen) {
    outline(g, rc.rectangle(60, 146, 196, 130, { ...PEN, fill: "#fff", fillStyle: "solid", seed: 81 }), "o card");
    outline(g, rc.rectangle(72, 158, 172, 106, { ...PEN, strokeWidth: 1.6, fill: "#cfe0f7", fillStyle: "hachure", hachureGap: 7, seed: 82 }), "o screen");
    outline(g, rc.line(72, 172, 244, 172, { ...PEN, strokeWidth: 1.4, seed: 83 }));
    for (let i = 0; i < 3; i++) el("circle", { cx: 80 + i * 8, cy: 165, r: 2.2, class: "pip" }, g);
    write(g, 158, 222, screen, 24, "screen-text");
    outline(g, rc.polygon([[44, 278], [272, 278], [292, 298], [24, 298]], { ...PEN, fill: "#bbb", fillStyle: "zigzag", hachureGap: 6, seed: 84 }), "o deck");
    outline(g, rc.rectangle(135, 284, 46, 9, { ...PEN, strokeWidth: 1.2, seed: 85 }));
}

/** A computer with its monitor, keyboard and mouse ( x 748…984, y 134…330 ): `lines` on its screen, the last strong, a cursor after it. */
function monitor(rc, g, lines) {
    outline(g, rc.rectangle(748, 134, 214, 142, { ...PEN, fill: "#fff", fillStyle: "solid", seed: 91 }), "o card");
    outline(g, rc.rectangle(760, 146, 190, 112, { ...PEN, strokeWidth: 1.6, fill: "#20242c", fillStyle: "solid", seed: 92 }), "o console");
    lines.forEach((line, i) => {
        const strong = i === lines.length - 1;
        el("text", { x: 770, y: strong ? 236 : 170 + i * 19, class: "console-text" + (strong ? " strong" : "") }, g, line);
    });
    el("rect", { x: 776 + 7.8 * (lines[lines.length - 1]?.length ?? 0), y: 226, width: 8, height: 13, class: "cursor" }, g);
    outline(g, rc.polygon([[843, 276], [867, 276], [873, 298], [837, 298]], { ...PEN, fill: "#bbb", fillStyle: "solid", seed: 93 }), "o deck");
    outline(g, rc.ellipse(855, 300, 96, 12, { ...PEN, fill: "#bbb", fillStyle: "solid", seed: 94 }), "o deck");
    outline(g, rc.polygon([[768, 308], [938, 308], [950, 326], [756, 326]], { ...PEN, fill: "#bbb", fillStyle: "zigzag", hachureGap: 6, seed: 95 }), "o deck");
    outline(g, rc.ellipse(976, 318, 16, 24, { ...PEN, strokeWidth: 1.6, fill: "#ddd", fillStyle: "solid", seed: 96 }), "o deck");
}

/** A router at (`x`, `y`), 64 × 26, its antennas up: `label` under it. */
function router(rc, g, x, y, label, seed) {
    outline(g, rc.line(x + 12, y, x + 5, y - 22, { ...PEN, strokeWidth: 2, seed }));
    outline(g, rc.line(x + 52, y, x + 59, y - 22, { ...PEN, strokeWidth: 2, seed: seed + 1 }));
    outline(g, rc.rectangle(x, y, 64, 26, { ...PEN, fill: "#e8e8e8", fillStyle: "solid", seed: seed + 2 }), "o box");
    for (let i = 0; i < 3; i++) el("circle", { cx: x + 16 + i * 11, cy: y + 13, r: 3, class: `led led-${i}` }, g);
    if (label) write(g, x + 32, y + 50, label, 19, "small");
}

/** An arrow by hand from (`x1`, `y1`) to (`x2`, `y2`): `dash` - dashed, `head` - false: none. */
function arrow(rc, g, x1, y1, x2, y2, seed, { dash = false, head = true, width = 2.2 } = {}) {
    outline(g, rc.line(x1, y1, x2, y2, { ...PEN, strokeWidth: width, seed, ...(dash ? { strokeLineDash: [8, 7] } : {}) }));
    if (head) arrowHead(rc, g, x2, y2, Math.atan2(y2 - y1, x2 - x1), seed + 1);
}

/** The head of an arrow, its tip at (`x`, `y`), pointing at `angle`. */
function arrowHead(rc, g, x, y, angle, seed) {
    const at = (back, side) => [x - Math.cos(angle) * back - Math.sin(angle) * side, y - Math.sin(angle) * back + Math.cos(angle) * side];
    outline(g, rc.polygon([[x, y], at(15, 7), at(15, -7)], { ...PEN, strokeWidth: 1.6, fill: "#333", fillStyle: "solid", seed }), "o head");
}

/** A picture `width` × `height`: the paper, its dots, the style; `more` - its own style. */
function frame(title, width, height, more = "") {
    const svg = el("svg", { xmlns: NS, viewBox: `0 0 ${width} ${height}`, width, height }, document.body);
    el("title", {}, svg, title);
    el("style", {}, svg, STYLE + more);
    const defs = el("defs", {}, svg);
    defs.innerHTML = '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3.5" result="b"/>'
        + '<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
        + '<pattern id="dots" width="20" height="20" patternUnits="userSpaceOnUse"><circle cx="1.5" cy="1.5" r="1.1" style="fill: var(--dot)"/></pattern>';
    for (const fill of ["fill: var(--paper); stroke: var(--line)", "fill: url(#dots)"])
        el("rect", { x: 1, y: 1, width: width - 2, height: height - 2, rx: 14, style: fill }, svg);
    return { svg, defs, rc: rough.svg(svg) };
}

function save(file, svg) {
    writeFileSync(new URL(`../${file}.svg`, import.meta.url), svg.outerHTML + "\n");
    svg.remove();
    console.log(`docs/${file}.svg`);
}

// ── what it is: B and A, each behind its NAT, met at the meeting point above the internet; the connection alive through it ──
{
    const { svg, defs, rc } = frame("SYN Mirror: two computers behind NAT meet at a point both can reach", 1000, 470);
    outline(svg, rc.path(cloudPath(500, 222, 250, 150), { ...PEN, strokeWidth: 2.4, fill: "#9cc4f0", fillStyle: "hachure", hachureGap: 9, hachureAngle: -30, seed: 33 }), "o cloud");
    write(svg, 500, 274, "Internet", 30);

    // the connection after the meeting: B, its NAT, up to the meeting point and down again, the NAT of A, A
    const wires = [
        ["w-b", "M 270 286 C 280 284 282 252 296 252 L 358 252 C 420 252 466 236 474 186 C 480 146 484 112 486 86"],
        ["w-a", "M 514 86 C 516 112 520 146 526 186 C 534 236 580 252 642 252 L 704 252 C 722 252 730 220 748 214"],
    ];
    for (const [id, d] of wires) {
        const seg = part(svg, "--b");
        el("path", { id, d, fill: "none" }, defs);
        outline(seg, rc.path(d, { ...PEN, strokeWidth: 2.6, seed: id === "w-b" ? 61 : 62 }));
        pulses(seg, id, 3, 2.2, true);
    }

    const meet = part(svg, "--meet", { class: "alive" });
    router(rc, meet, 468, 60, "", 80);
    write(meet, 610, 76, "meeting point", 26);
    write(meet, 610, 100, "SYN Mirror: OpenWrt or Linux", 18, "small");
    write(svg, 330, 52, "port 40000: ports are given", 18, "small");
    write(svg, 330, 74, "40001-49999: the meetings", 18, "small");
    router(rc, el("g", { class: "alive" }, svg), 296, 238, "its NAT", 72);
    router(rc, el("g", { class: "alive" }, svg), 642, 238, "its NAT", 76);

    const b = part(svg, "--b");
    write(b, 158, 100, "the client: connects to the port", 19, "small");
    write(b, 158, 126, "Client", 30);
    laptop(rc, b, "a browser");
    const a = part(svg, "--a");
    write(a, 855, 100, "the server: opens a port, waits", 19, "small");
    write(a, 855, 126, "Server", 30);
    monitor(rc, a, ["> the server", "port given: 41933", "knocks, dials", "client came: in"]);

    write(part(svg, "--b"), 30, 372, "The client connects: it dials out", 21, "", "start");
    write(part(svg, "--a"), 970, 372, "The server opens a port: it dials out too", 21, "", "end");
    write(part(svg, "--b"), 500, 418, "After the meeting: one TCP connection, client to server", 26);
    write(svg, 500, 446, "passed by the kernel of the meeting point like a forwarded port, no program in between", 19, "small");
    save("overview", svg);
}

// ── the meeting, step by step: the five on their lines, the packets between them; the steps lit one after another ──
{
    const STEPS = 8, EACH = 2.5, CYCLE = STEPS * EACH;
    const more = `.step { opacity: .62; animation: lit ${CYCLE}s infinite; }\n`
        + Array.from({ length: STEPS }, (_, i) => `#step-${i} { animation-delay: ${i * EACH - CYCLE}s; }\n`).join("")
        + `@keyframes lit { 0%, ${(100 / STEPS) - 0.5}% { opacity: 1; } ${100 / STEPS}%, 100% { opacity: .62; } }\n`;
    const { svg, defs, rc } = frame("SYN Mirror: the meeting, step by step", 1000, 820, more);
    const A = 90, NA = 285, M = 500, NB = 715, B = 910, TOP = 160, BOTTOM = 800;

    // who is who, on top: A and B small, the routers
    const a = part(svg, "--a");
    monitor(rc, el("g", { transform: `translate(${A - 866 * 0.42} ${18 - 134 * 0.42}) scale(0.42)` }, a), ["> A", "", "", "waits"]);
    write(a, A, 128, "Server", 24);
    write(a, A, 150, "opens a port, waits", 16, "small");
    for (const [x, label, seed] of [[NA, "its NAT", 100], [NB, "its NAT", 110]]) {
        const g = el("g", {}, svg);
        router(rc, g, x - 32, 64, "", seed);
        write(g, x, 128, label, 22);
    }
    const meet = part(svg, "--meet");
    router(rc, meet, M - 32, 64, "", 120);
    write(meet, M, 128, "meeting point", 24);
    const b = part(svg, "--b");
    laptop(rc, el("g", { transform: `translate(${B - 158 * 0.42} ${22 - 146 * 0.42}) scale(0.42)` }, b), "");
    write(b, B, 128, "Client", 24);
    write(b, B, 150, "connects to it", 16, "small");
    for (const [x, seed] of [[A, 130], [NA, 132], [M, 134], [NB, 136], [B, 138]])
        outline(svg, rc.line(x, TOP, x, BOTTOM, { ...PEN, strokeWidth: 1.6, strokeLineDash: [6, 8], seed }), "o life");

    const step = (i, pen) => part(svg, pen, { id: `step-${i}`, class: "step" });
    const cross = (g, x, y) => write(g, x, y + 8, "✕", 30, "", "middle").setAttribute("style", "fill: var(--bad)");

    // 1: a port, asked and given
    let g = step(0, "--a");
    write(g, (A + M) / 2, 172, "① The server asks for a port: UDP to 40000", 20);
    arrow(rc, g, A, 184, M, 184, 200);
    arrow(rc, g, M, 222, A, 222, 202, { dash: true });
    write(g, (A + M) / 2, 246, "the answer, 2 bytes: port 41933", 18);
    write(part(g, "--meet"), M + 16, 210, "port 41933, given to the id of the server", 18, "", "start");

    // 2: the knock
    g = step(1, "--a");
    write(g, (A + M) / 2, 286, "② It opens it: UDP to 41933, password, id", 20);
    arrow(rc, g, A, 298, M, 298, 210);
    write(part(g, "--meet"), M + 16, 304, "the port opens: the id is the server's", 18, "", "start");

    // 3: A dials, dropped, every second
    g = step(2, "--a");
    write(g, (A + M) / 2, 348, "③ The server waits: a SYN, every second", 20);
    arrow(rc, g, A, 360, M - 14, 360, 220);
    cross(g, M, 360);
    write(part(g, "--meet"), M + 22, 366, "dropped; where the server is - remembered", 18, "", "start");
    write(g, (A + M) / 2, 392, "always from the same port:", 17, "small");
    write(g, (A + M) / 2, 412, "the NAT of the server keeps its door open", 17, "small");

    // 4: B dials the same port
    g = step(3, "--b");
    write(g, (M + B) / 2, 462, "④ The client connects: SYN to 41933", 20);
    arrow(rc, g, B, 474, M, 474, 230);

    // 5: the SYN of B, rewritten, let in by the NAT of A as an answer
    g = step(4, "--meet");
    write(g, (A + M) / 2, 520, "⑤ the SYN of the client, rewritten:", 20);
    write(g, (A + M) / 2, 542, "from the very address the server dials", 20);
    arrow(rc, g, M, 556, A, 556, 240);
    write(part(g, "--b"), NA, 584, "✓ an answer to the SYN of the server: let in", 17);

    // 6: A answers: one connection of the two dialing
    g = step(5, "--a");
    write(g, (A + B) / 2, 628, "⑥ SYN-ACK: the server takes the SYN of the client as the other half of its own - TCP simultaneous open", 19);
    arrow(rc, g, A, 640, B, 640, 250);

    // 7: B acknowledges: set up
    g = step(6, "--b");
    write(g, (A + B) / 2, 684, "⑦ ACK: the connection is set up; the port closes for anyone else, and stays given to the server", 19);
    arrow(rc, g, B, 696, A, 696, 260);

    // 8: the data, both ways, the kernel rewriting
    g = step(7, "--b");
    write(g, (A + B) / 2, 742, "⑧ data, both ways: the kernel of the meeting point rewrites the addresses, as for a forwarded port", 19);
    el("path", { id: "data", d: `M ${A} 762 L ${B} 762`, fill: "none" }, defs);
    outline(g, rc.line(A, 762, B, 762, { ...PEN, strokeWidth: 3, seed: 270 }));
    arrowHead(rc, g, B, 762, 0, 272);
    arrowHead(rc, g, A, 762, Math.PI, 274);
    pulses(g, "data", 4, 3, true);
    save("meeting", svg);
}

// ── why the NAT of A lets the connection in: the SYN of A, the SYN of B, the same SYN rewritten - the answer the NAT waits for ──
{
    const { svg, rc } = frame("SYN Mirror: why the NAT of the server lets the connection in", 1000, 600);
    write(svg, 500, 42, "A NAT lets in only answers: packets from the address its own computer sent to", 23);
    write(svg, 500, 70, "the NAT of the server 198.51.100.7 · the meeting point 203.0.113.5, port 41933 · the NAT of the client 192.0.2.44", 18, "small");

    /** A packet: a card, its title, from and to, a note under. */
    const packet = (pen, x, y, title, from, fromNote, to, toNote, note, seed, w = 440) => {
        const g = part(svg, pen);
        outline(g, rc.rectangle(x, y, w, 152, { ...PEN, fill: "#fff", fillStyle: "solid", seed }), "o card");
        write(g, x + 22, y + 34, title, 22, "", "start");
        for (const [k, word, addr, extra] of [[0, "from", from, fromNote], [1, "to", to, toNote]]) {
            write(svg, x + 22, y + 70 + k * 28, word, 19, "small", "start");
            el("text", { x: x + 72, y: y + 70 + k * 28, class: "mono" }, svg, addr);
            if (extra) write(svg, x + 252, y + 70 + k * 28, extra, 16, "small", "start");
        }
        write(svg, x + 22, y + 134, note, 17, "small", "start");
        return g;
    };
    packet("--a", 30, 100, "③ The SYN of the server, out of its NAT", "198.51.100.7:62000", "", "203.0.113.5:41933", "",
        "its NAT notes: answers from 203.0.113.5:41933 come in", 300);
    packet("--b", 530, 100, "④ The SYN of the client, at the meeting point", "192.0.2.44:31000", "", "203.0.113.5:41933", "",
        "the same port the server dials", 310);
    packet("--meet", 300, 318, "⑤ The same SYN, sent on to the server", "203.0.113.5:41933", "was the client", "198.51.100.7:62000", "where the server's SYNs came from",
        "exactly ③ reversed: for the NAT of the server it is the answer", 320, 480);

    const turn = part(svg, "--meet");
    outline(turn, rc.path("M 760 254 C 760 292 690 300 620 314", { ...PEN, strokeWidth: 2.4, seed: 330 }));
    arrowHead(rc, turn, 620, 314, Math.atan2(314 - 304, 620 - 650), 331);
    write(turn, 776, 288, "the meeting point", 20, "", "start");
    write(turn, 776, 310, "rewrites both addresses", 20, "", "start");

    // the NAT of A: ⑤ goes in
    const nat = part(svg, "--b", { class: "alive" });
    router(rc, nat, 92, 380, "NAT of the server", 340);
    arrow(rc, nat, 298, 394, 166, 394, 342);
    write(nat, 232, 380, "let in", 19);

    write(part(svg, "--b"), 500, 520, "✓ The NAT of the server lets ⑤ in, and the server answers it: the connection is set up", 23);
    write(part(svg, "--bad"), 500, 560, "✗ The SYN of the client as it was, from 192.0.2.44:31000, would be dropped: the server never sent there", 23);
    save("nat", svg);
}

// ── a meeting point whose address changes: it writes it into a record of one of a fixed address; the server reads it there, then
// meets as always; the address changes, written again at once, read again - the same port at the new address ──
{
    const STEPS = 6, EACH = 3, CYCLE = STEPS * EACH;
    const more = `.step { opacity: .55; animation: lit ${CYCLE}s infinite; }\n`
        + Array.from({ length: STEPS }, (_, i) => `#change-${i} { animation-delay: ${i * EACH - CYCLE}s; }\n`).join("")
        + `@keyframes lit { 0%, ${(100 / STEPS) - 0.5}% { opacity: 1; } ${100 / STEPS}%, 100% { opacity: .55; } }\n`;
    const { svg, defs, rc } = frame("SYN Mirror: a meeting point whose address changes", 1000, 860, more);
    const A = 100, S = 380, D = 640, B = 900, TOP = 170, BOTTOM = 840;

    const a = part(svg, "--a");
    monitor(rc, el("g", { transform: `translate(${A - 866 * 0.42} ${18 - 134 * 0.42}) scale(0.42)` }, a), ["> server", "", "", "waits"]);
    write(a, A, 128, "Server", 24);
    write(a, A, 150, "has the line, reads, knocks", 16, "small");
    const s = part(svg, "--meet");
    router(rc, s, S - 32, 64, "", 400);
    write(s, S, 128, "meeting point S", 24);
    write(s, S, 150, "a fixed address: keeps the record", 16, "small");
    const d = part(svg, "--meet", { class: "alive" });
    router(rc, d, D - 32, 64, "", 410);
    write(d, D, 128, "meeting point D", 24);
    write(d, D, 150, "its address changes", 16, "small");
    const b = part(svg, "--b");
    laptop(rc, el("g", { transform: `translate(${B - 158 * 0.42} ${22 - 146 * 0.42}) scale(0.42)` }, b), "");
    write(b, B, 128, "Client", 24);
    write(b, B, 150, "connects, as to any address", 16, "small");
    for (const [x, seed] of [[A, 420], [S, 422], [D, 424], [B, 426]])
        outline(svg, rc.line(x, TOP, x, BOTTOM, { ...PEN, strokeWidth: 1.6, strokeLineDash: [6, 8], seed }), "o life");

    const step = (i, pen) => part(svg, pen, { id: `change-${i}`, class: "step" });

    // 1: D writes its address
    let g = step(0, "--meet");
    write(g, (S + D) / 2, 184, "① D writes: its write key + the port 41000", 19);
    arrow(rc, g, D, 196, S, 196, 430);
    arrow(rc, g, S, 228, D, 228, 432, { dash: true });
    write(g, (S + D) / 2, 252, "the answer: you are 198.51.100.20", 17, "small");
    write(g, S - 14, 290, "record: 198.51.100.20, port 41000, just now", 17, "", "end");
    write(g, D + 14, 290, "again each 20 s, and at once when its address changes", 16, "small", "start");

    // 2: the server reads it
    g = step(1, "--a");
    write(g, (A + S) / 2, 330, "② The server reads: its read key", 19);
    arrow(rc, g, A, 342, S, 342, 440);
    arrow(rc, g, S, 374, A, 374, 442, { dash: true });
    write(g, (A + S) / 2, 398, "198.51.100.20, port 41000, 0 min old", 17, "small");

    // 3: the meeting, as always, at that address
    g = step(2, "--a");
    write(g, (A + D) / 2 + 60, 438, "③ It knocks at 198.51.100.20:41000 and dials it: the meeting, as always", 19);
    arrow(rc, g, A, 450, D, 450, 450);
    const bg = part(g, "--b");
    arrow(rc, bg, B, 486, D, 486, 452);
    write(bg, (D + B) / 2, 478, "198.51.100.20:41000", 16, "small");
    el("path", { id: "met-1", d: `M ${D} 510 L ${A} 510`, fill: "none" }, defs);
    outline(bg, rc.line(A, 510, D, 510, { ...PEN, strokeWidth: 2.4, seed: 454 }));
    outline(bg, rc.line(D, 510, B, 510, { ...PEN, strokeWidth: 2.4, seed: 456 }));
    pulses(bg, "met-1", 3, 2.6, true);

    // 4: the address of D changes; it writes at once
    g = step(3, "--meet");
    write(g, D, 560, "④ The provider gives D another address: 203.0.113.77", 19);
    arrow(rc, g, D, 576, S, 576, 460);
    write(g, S - 14, 604, "record: 203.0.113.77, port 41000", 17, "", "end");
    write(g, (S + D) / 2 + 30, 604, "written at once", 16, "small");

    // 5: the server reads again
    g = step(4, "--a");
    write(g, (A + S) / 2, 648, "⑤ The server reads again, each 30 s", 19);
    arrow(rc, g, A, 660, S, 660, 470);
    arrow(rc, g, S, 690, A, 690, 472, { dash: true });
    write(g, (A + S) / 2, 714, "203.0.113.77, port 41000", 17, "small");

    // 6: the same port at the new address
    g = step(5, "--a");
    write(g, (A + D) / 2 + 60, 754, "⑥ It knocks at 203.0.113.77:41000: the same port, D kept it", 19);
    arrow(rc, g, A, 766, D, 766, 480);
    const bg2 = part(g, "--b");
    arrow(rc, bg2, B, 800, D, 800, 482);
    write(bg2, (D + B) / 2, 792, "203.0.113.77:41000", 16, "small");
    write(g, (A + D) / 2, 826, "the server shows the client its new line", 17, "small");
    save("changing", svg);
}

// ── the lines: what each part of them is ──
{
    const { svg, rc } = frame("SYN Mirror: the lines, part by part", 1000, 720);
    write(svg, 500, 44, "The lines the page of the meeting point copies: each part, what it is", 24);
    const CW = 11.2, X = 50;
    let seed = 500;

    /** A line at `y`: its parts [ text, pen, label ], each underlined by hand and named under it; `title` above. */
    const line = (y, title, parts) => {
        write(svg, X, y - 30, title, 20, "", "start");
        let x = X;
        parts.forEach(([text, pen, label], i) => {
            const g = part(svg, pen);
            const w = text.length * CW;
            el("text", { x, y, class: "mono", textLength: w, lengthAdjust: "spacingAndGlyphs", style: "font-size: 19px; fill: var(--pen)" }, g, text);
            if (label) {
                outline(g, rc.line(x + 2, y + 9, x + w - 2, y + 9, { ...PEN, strokeWidth: 1.6, seed: seed++ }));
                write(g, x + w / 2, y + 30 + (i % 2) * 20, label, 15, "", "middle");
            }
            x += w;
        });
    };

    line(116, "A port given at each start, the meeting point at a fixed address", [
        ["Tr7kQ2xZp4Lm9sWd", "--a", "the password: 16"], ["@", "--muted", "ask for a port"], ["203.0.113.7", "--meet", "the meeting point"],
        [":40000", "--meet", "its port of requests"]]);
    line(256, "A fixed port: always the same, its key opens it", [
        ["Fx2pL8wNq7Rk3mZa", "--a", "the key of the port: 16"], ["=", "--muted", "knock at once, ask nothing"], ["203.0.113.7", "--meet", "the meeting point"],
        [":41000", "--meet", "the fixed port"]]);
    line(396, "The meeting point's address changes: read it where its record is kept", [
        ["Fx2pL8wNq7Rk3mZa", "--a", "password or key"], ["=", "--muted", "@ or =, as above"], ["Rk8mP2qLx3Vb7NtY", "--b", "a read key: 16"],
        ["@198.51.100.9:40000", "--meet", "S: keeps the record"], [",", "--muted", "else"], ["Hx4nT7wAe2Kq9VsM@…", "--b", "another S, if S does not answer"]]);
    line(536, "For the meeting point whose address changes: where it writes it", [
        ["Wk3vB9xQm5Tz2Lpe", "--meet", "the write key: 16"], ["/", "--muted", "and"], ["Rk8mP2qLx3Vb7NtY", "--b", "a read key: for its lines"],
        ["@198.51.100.9:40000", "--meet", "S, which keeps the record"]]);

    write(part(svg, "--b"), 500, 640, "The client gets only an address and a port: 203.0.113.7:41000 - nothing else, nothing installed", 21);
    write(svg, 500, 676, "The keys are letters and digits: a line goes into a message, a console, a field, as it is", 18, "small");
    save("lines", svg);
}

// ── a port given at each start, and a fixed one: what the server sends, what the client gets ──
{
    const { svg, rc } = frame("SYN Mirror: a port given at each start, and a fixed port", 1000, 640);
    write(svg, 500, 44, "Two ways to a port of meeting", 26);
    const L = 250, R = 750;
    write(part(svg, "--a"), L, 92, "A port given at each start", 24);
    write(svg, L, 116, "the line: password@meeting point:40000", 17, "small");
    write(part(svg, "--a"), R, 92, "A fixed port", 24);
    write(svg, R, 116, "the line: key=meeting point:41000", 17, "small");
    outline(svg, rc.line(500, 80, 500, 560, { ...PEN, strokeWidth: 1.4, strokeLineDash: [6, 8], seed: 600 }), "o life");

    /** A box of a step at `y`, its words in it; its bottom returned. */
    const box = (pen, x, y, w, lines, seed) => {
        const g = part(svg, pen);
        outline(g, rc.rectangle(x - w / 2, y, w, 18 + lines.length * 22, { ...PEN, fill: "#fff", fillStyle: "solid", seed }), "o card");
        lines.forEach((t, i) => write(g, x, y + 28 + i * 22, t, i ? 16 : 19, i ? "small" : ""));
        return y + 18 + lines.length * 22;
    };
    const down = (x, y1, y2, seed) => arrow(rc, svg, x, y1 + 4, x, y2 - 4, seed, { width: 1.8 });

    let y = box("--a", L, 140, 380, ["① ask: password + id → 40000", "24 bytes"], 610);
    down(L, y, 232, 612);
    y = box("--meet", L, 232, 380, ["② a free port: 41933", "2 bytes back, given to the id"], 614);
    down(L, y, 324, 616);
    y = box("--a", L, 324, 380, ["③ knock: password + id → 41933", "24 bytes, every second"], 618);
    down(L, y, 416, 620);
    box("--b", L, 416, 380, ["the client: 203.0.113.7:41933", "sent to it by the server"], 622);
    write(part(svg, "--bad"), L, 516, "↻ the next start: another port, another line", 19);
    write(svg, L, 542, "a minute after the server stops, the port is given to others", 16, "small");

    y = box("--a", R, 140, 380, ["① knock: the key → 41000", "16 bytes, every second; nothing asked"], 630);
    write(part(svg, "--meet"), R, 290, "the port is set aside for the key", 17, "small");
    down(R, y, 416, 632);
    box("--b", R, 416, 380, ["the client: 203.0.113.7:41000", "kept once, in its program"], 634);
    write(part(svg, "--b"), R, 516, "↻ the next start: the same port, the same line", 19);
    write(svg, R, 542, "nobody else gets it, ever; closed while the server does not knock", 16, "small");

    write(svg, 500, 604, "Both: the server dials the port every second, the client dials it once - the meeting is the same", 20);
    save("fixed", svg);
}

// ── how the server finds the meeting point whose address changes: the reads in turn, the freshest, again each 30 s ──
{
    const { svg, rc } = frame("SYN Mirror: how the server finds a meeting point whose address changes", 1000, 760);
    write(svg, 500, 44, "How the server finds a meeting point whose address changes", 26);

    /** A box: a step ( card ) or a question ( diamond ), `x` its middle, `y` its top. */
    const step = (pen, x, y, w, h, lines, seed, diamond = false) => {
        const g = part(svg, pen);
        if (diamond) outline(g, rc.polygon([[x, y], [x + w / 2, y + h / 2], [x, y + h], [x - w / 2, y + h / 2]], { ...PEN, fill: "#fff", fillStyle: "solid", seed }), "o card");
        else outline(g, rc.rectangle(x - w / 2, y, w, h, { ...PEN, fill: "#fff", fillStyle: "solid", seed }), "o card");
        const top = y + h / 2 - (lines.length - 1) * 11 + 6;
        lines.forEach((t, i) => write(g, x, top + i * 22, t, i ? 15 : 18, i ? "small" : ""));
    };
    const label = (x, y, t, anchor = "middle") => write(svg, x, y, t, 16, "small", anchor);
    const go = (x1, y1, x2, y2, seed) => arrow(rc, svg, x1, y1, x2, y2, seed, { width: 1.8 });

    step("--a", 500, 76, 440, 56, ["Read: the next read key@S of the line", "UDP, 16 bytes; up to 3 tries, 1 s each"], 700);
    go(500, 134, 500, 166, 702);
    step("--meet", 500, 168, 280, 110, ["S answered?", "7 bytes"], 704, true);
    // no answer: another S, or none
    go(640, 223, 748, 223, 706);
    label(694, 214, "no");
    step("--meet", 860, 196, 220, 56, ["Another S in the line?"], 708);
    go(860, 194, 860, 120, 710);
    go(860, 104, 724, 104, 712);
    label(872, 160, "yes: read it", "start");
    go(860, 254, 860, 316, 714);
    label(872, 290, "no", "start");
    step("--a", 860, 318, 220, 80, ["None fresh: the freshest", "none at all: say so,", "read again in 5 s"], 716);
    // an answer: how fresh
    go(500, 280, 500, 318, 718);
    label(512, 304, "yes", "start");
    step("--meet", 500, 320, 300, 110, ["Written in the last 2 min?", "its 7th byte: the minutes"], 720, true);
    go(350, 375, 246, 375, 722);
    label(298, 366, "no: kept");
    step("--a", 140, 348, 200, 56, ["Ask the next S", "the same way"], 724);
    go(140, 346, 140, 120, 726);
    go(140, 104, 276, 104, 728);
    go(500, 432, 500, 470, 730);
    label(512, 456, "yes", "start");
    go(860, 400, 704, 486, 732);

    step("--a", 500, 472, 400, 66, ["The address and the port of the meeting point", "@: ask it for a port, the same id   =: knock the key"], 734);
    go(500, 540, 500, 574, 736);
    step("--a", 500, 576, 400, 56, ["Knock and dial, every second", "from the same local port"], 738);
    go(500, 634, 500, 668, 740);
    step("--a", 500, 670, 400, 56, ["30 s later: read again, from the top", "moved: there with the same id or key; a new line"], 742);
    outline(svg, rc.path("M 300 698 C 40 698 40 104 136 104", { ...PEN, strokeWidth: 1.8, strokeLineDash: [8, 7], seed: 744 }));
    write(svg, 66, 600, "each 30 s", 16, "small", "start");
    save("reading", svg);
}

// ── the packets, byte by byte, and what the meeting point tells by their length ──
{
    const { svg, rc } = frame("SYN Mirror: the packets, byte by byte", 1000, 690);
    write(svg, 500, 44, "Every packet: UDP, its payload alone - told apart by its length and its first 16 bytes", 23);
    const X = 290, B = 10;
    let seed = 800;

    /** A packet at `y`: its fields [ bytes, words, pen ], as wide as their bytes; the name on the left, the answer on the right. */
    const packet = (y, name, to, fields, answer) => {
        write(svg, 40, y + 22, name, 19, "", "start");
        write(svg, 40, y + 44, to, 15, "small", "start");
        let x = X;
        for (const [n, words, pen] of fields) {
            const g = part(svg, pen);
            const w = words ? Math.max(n * B, 46) : Math.max(n * B, 18);
            outline(g, rc.rectangle(x, y + 4, w, 34, { ...PEN, strokeWidth: 1.6, fill: "#fff", fillStyle: "solid", seed: seed++ }), "o card");
            write(g, x + w / 2, y + 27, words, 15);
            write(svg, x + w / 2, y + 56, `${n}`, 13, "small");
            x += w;
        }
        write(svg, x + 12, y + 27, `= ${fields.reduce((s, f) => s + f[0], 0)} bytes`, 16, "", "start");
        write(part(svg, answer[1]), 960, y + 27, answer[0], 15, "", "end");
    };
    const none = ["no answer", "--muted"];
    packet(78, "Ask for a port", "→ its port of requests", [[16, "password", "--a"], [8, "id", "--a"]], ["← 2: the port", "--meet"]);
    packet(146, "Knock", "→ the port of meeting", [[16, "password", "--a"], [8, "id", "--a"]], none);
    packet(214, "Hold", "→ the port of meeting", [[16, "password", "--a"], [8, "id", "--a"], [1, "", "--muted"]], none);
    packet(282, "Knock: fixed port", "→ the fixed port", [[16, "its key", "--a"]], none);
    packet(350, "Hold: fixed port", "→ the fixed port", [[16, "its key", "--a"], [1, "", "--muted"]], none);
    packet(418, "Write: D → S", "→ the port of requests of S", [[16, "write key", "--meet"], [2, "port", "--meet"]], ["← 4: the address seen", "--meet"]);
    packet(486, "Read: server → S", "→ the port of requests of S", [[16, "read key", "--b"]], ["← 7: address, port, minutes", "--meet"]);

    write(svg, 500, 586, "A wrong one - another length, a key not of the settings - gets no answer, and counts as a wrong password", 19);
    write(svg, 500, 616, "Each answer is shorter than its request: the meeting point multiplies the traffic of nobody", 17, "small");
    write(svg, 500, 644, "A port: 2 bytes, high first · an address: 4 bytes · the id: 8 random bytes of the server, the same in all its packets", 17, "small");
    save("packets", svg);
}
