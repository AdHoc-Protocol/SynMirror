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
