// SPDX-License-Identifier: GPL-3.0-or-later
//
// Config defaults and value parsing for ~/.config/riley-overview/config.xml (schema data/config.xsd).
// Pure logic, no Quickshell. Specified in docs/design.md "Config".
//
//   DEFAULTS: the default values (below; data/config.example.xml spells them out).
//   parseConfig(text) -> { ok, config, errors }
//     ok true: config holds the file's values, defaults for missing elements; errors [].
//     ok false: the file is not used at all; config is a copy of DEFAULTS; errors says why (one or more strings).
//     Always a fresh config object.
//
// The shell checks the file with xmllint against the schema first; parseConfig applies the same rules itself
// (structure, namespace, version, ranges), so a value the schema would reject is never used. The XML reader below
// is a small strict one for this one flat format: declaration, comments, processing instructions, elements,
// attributes, text, CDATA and character references. A DOCTYPE is refused.

export const DEFAULTS = Object.freeze({
    margin: 24,
    stripHeight: 120,
    stripSpacing: 16,
    searchHeight: 40,
    sectionGap: 16,
    windowSpacing: 24,
    maxScale: 1.0,
    animationMs: 200,
    launcher: "fuzzel",
});

export const NAMESPACE = "urn:riley-overview:config";

// Element name -> [key, kind, min, max]. "uint": XSD unsignedInt restricted to [0-9]+; "scale": xs:decimal with
// 0 < v <= 1; "line": xs:string, one line, not only whitespace, trimmed here.
const ELEMENTS = {
    "margin": ["margin", "uint", 0, 400],
    "strip-height": ["stripHeight", "uint", 40, 400],
    "strip-spacing": ["stripSpacing", "uint", 0, 200],
    "search-height": ["searchHeight", "uint", 20, 200],
    "section-gap": ["sectionGap", "uint", 0, 200],
    "window-spacing": ["windowSpacing", "uint", 0, 200],
    "max-scale": ["maxScale", "scale", 0, 1],
    "animation-ms": ["animationMs", "uint", 0, 200],
    "launcher": ["launcher", "line", 0, 0],
};

const NAME = /^[A-Za-z_][A-Za-z0-9_.\-]*(?::[A-Za-z_][A-Za-z0-9_.\-]*)?/;
const XML_WS = /^[ \t\r\n]*$/;

function freshDefaults() {
    const o = {};
    for (const k in DEFAULTS) o[k] = DEFAULTS[k];
    return o;
}

class XmlError extends Error {}

function decodeRefs(s) {
    return s.replace(/&([^;&<]*);|&/g, (all, ref) => {
        if (ref === undefined) throw new XmlError("bare '&'");
        switch (ref) {
            case "lt": return "<";
            case "gt": return ">";
            case "amp": return "&";
            case "quot": return "\"";
            case "apos": return "'";
        }
        let cp = NaN;
        if (/^#x[0-9A-Fa-f]+$/.test(ref)) cp = parseInt(ref.slice(2), 16);
        else if (/^#[0-9]+$/.test(ref)) cp = parseInt(ref.slice(1), 10);
        if (!(cp === 0x9 || cp === 0xA || cp === 0xD || (cp >= 0x20 && cp <= 0xD7FF) ||
              (cp >= 0xE000 && cp <= 0xFFFD) || (cp >= 0x10000 && cp <= 0x10FFFF)))
            throw new XmlError("unknown or bad reference '&" + ref + ";'");
        return String.fromCodePoint(cp);
    });
}

// Parses the document into { name, attrs: [[name, value]], children: [element], text } (text: the element's
// character data, concatenated). Throws XmlError on anything that is not well-formed.
function parseXml(src) {
    let s = src.replace(/\r\n?/g, "\n");
    if (s.charCodeAt(0) === 0xFEFF) s = s.slice(1);
    let i = 0;

    function fail(msg) {
        const line = s.slice(0, i).split("\n").length;
        throw new XmlError("line " + line + ": " + msg);
    }
    function skipWs() { while (i < s.length && " \t\n".indexOf(s[i]) >= 0) i++; }
    function name() {
        const m = NAME.exec(s.slice(i, i + 256));
        if (!m) fail("expected a name");
        i += m[0].length;
        return m[0];
    }
    function comment() {
        const end = s.indexOf("-->", i + 4);
        if (end < 0) fail("unterminated comment");
        if (s.slice(i + 4, end).indexOf("--") >= 0 || s[end - 1] === "-") fail("'--' inside a comment");
        i = end + 3;
    }
    function pi(atStart) {
        i += 2;
        const target = name();
        if (target.toLowerCase() === "xml" && !(atStart && target === "xml"))
            fail("XML declaration not at the start");
        const end = s.indexOf("?>", i);
        if (end < 0) fail("unterminated processing instruction");
        if (target === "xml") {
            const body = s.slice(i, end);
            if (!/^\s+version\s*=\s*(["'])1\.[0-9]+\1(\s+encoding\s*=\s*(["'])[A-Za-z][A-Za-z0-9._\-]*\3)?(\s+standalone\s*=\s*(["'])(yes|no)\5)?\s*$/.test(body))
                fail("bad XML declaration");
        }
        i = end + 2;
    }
    // Comments, processing instructions and whitespace outside the root element.
    function misc() {
        for (;;) {
            skipWs();
            if (s.startsWith("<!--", i)) comment();
            else if (s.startsWith("<?", i)) pi(false);
            else if (s.startsWith("<!DOCTYPE", i)) fail("DOCTYPE is not allowed");
            else return;
        }
    }
    function element() {
        if (s[i] !== "<") fail("expected '<'");
        i++;
        const el = { name: name(), attrs: [], children: [], text: "" };
        const seen = {};
        for (;;) {
            const before = i;
            skipWs();
            if (s.startsWith("/>", i)) { i += 2; return el; }
            if (s[i] === ">") { i++; break; }
            if (i === before) fail("expected whitespace before an attribute");
            const an = name();
            if (seen[an]) fail("attribute '" + an + "' twice");
            seen[an] = true;
            skipWs();
            if (s[i] !== "=") fail("expected '=' after attribute '" + an + "'");
            i++;
            skipWs();
            const q = s[i];
            if (q !== "\"" && q !== "'") fail("attribute value not quoted");
            const end = s.indexOf(q, i + 1);
            if (end < 0) fail("unterminated attribute value");
            const raw = s.slice(i + 1, end);
            if (raw.indexOf("<") >= 0) fail("'<' in attribute value");
            // Attribute-value normalisation: literal whitespace characters become spaces.
            el.attrs.push([an, decodeRefs(raw.replace(/[\t\n]/g, " "))]);
            i = end + 1;
        }
        for (;;) {
            if (i >= s.length) fail("element '" + el.name + "' not closed");
            if (s.startsWith("</", i)) {
                i += 2;
                const n = name();
                if (n !== el.name) fail("'</" + n + ">' closes '<" + el.name + ">'");
                skipWs();
                if (s[i] !== ">") fail("expected '>'");
                i++;
                return el;
            }
            if (s.startsWith("<!--", i)) { comment(); continue; }
            if (s.startsWith("<![CDATA[", i)) {
                const end = s.indexOf("]]>", i + 9);
                if (end < 0) fail("unterminated CDATA section");
                el.text += s.slice(i + 9, end);
                i = end + 3;
                continue;
            }
            if (s.startsWith("<?", i)) { pi(false); continue; }
            if (s[i] === "<") { el.children.push(element()); continue; }
            let end = s.indexOf("<", i);
            if (end < 0) end = s.length;
            const raw = s.slice(i, end);
            if (raw.indexOf("]]>") >= 0) fail("']]>' in text");
            el.text += decodeRefs(raw);
            i = end;
        }
    }

    if (/^<\?xml[ \t\n]/.test(s)) pi(true);
    misc();
    if (s[i] !== "<") fail("no root element");
    const root = element();
    misc();
    if (i !== s.length) fail("content after the root element");
    return root;
}

// Resolves an element's namespace from its own and its ancestors' xmlns declarations. Returns [ns, localName,
// the in-scope map for its children]; non-namespace attributes come back in `attrs`.
function resolve(el, scope, errors) {
    const inScope = Object.assign({}, scope);
    const attrs = [];
    for (const [n, v] of el.attrs) {
        if (n === "xmlns") inScope[""] = v;
        else if (n.startsWith("xmlns:")) {
            if (v === "") errors.push("empty namespace for prefix '" + n.slice(6) + "'");
            inScope[n.slice(6)] = v;
        } else attrs.push([n, v]);
    }
    const colon = el.name.indexOf(":");
    const prefix = colon < 0 ? "" : el.name.slice(0, colon);
    const local = colon < 0 ? el.name : el.name.slice(colon + 1);
    if (prefix !== "" && !(prefix in inScope)) errors.push("unbound prefix '" + prefix + "'");
    return { ns: inScope[prefix] || "", local: local, attrs: attrs, scope: inScope };
}

function value(elName, spec, text, errors) {
    const [key, kind, min, max] = spec;
    if (kind === "line") {
        if (/[\r\n]/.test(text)) { errors.push("<" + elName + "> must be one line"); return undefined; }
        if (!/[^ \t\r\n]/.test(text)) { errors.push("<" + elName + "> is blank"); return undefined; }
        return text.trim();
    }
    // xs:unsignedInt and xs:decimal collapse whitespace, so surrounding whitespace is allowed.
    const t = text.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "");
    if (kind === "uint") {
        if (!/^[0-9]+$/.test(t)) { errors.push("<" + elName + "> '" + t + "' is not a whole number"); return undefined; }
        const n = parseInt(t, 10);
        if (n < min || n > max) { errors.push("<" + elName + "> " + n + " is outside " + min + " to " + max); return undefined; }
        return n;
    }
    if (!/^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(t)) { errors.push("<" + elName + "> '" + t + "' is not a decimal"); return undefined; }
    const x = parseFloat(t);
    if (!(x > min && x <= max)) { errors.push("<" + elName + "> " + t + " is not above " + min + " and at most " + max); return undefined; }
    return x;
}

export function parseConfig(text) {
    const errors = [];
    const config = freshDefaults();
    let root;
    try {
        if (typeof text !== "string") throw new XmlError("no text");
        root = parseXml(text);
    } catch (e) {
        if (!(e instanceof XmlError)) throw e;
        return { ok: false, config: freshDefaults(), errors: ["not well-formed XML: " + e.message] };
    }
    const r = resolve(root, {}, errors);
    if (r.local !== "overview" || r.ns !== NAMESPACE)
        errors.push("root must be <overview xmlns=\"" + NAMESPACE + "\">, found <" + root.name + "> in namespace '" + r.ns + "'");
    let version = null;
    for (const [n, v] of r.attrs) {
        if (n === "version") version = v;
        else errors.push("unknown attribute '" + n + "' on <overview>");
    }
    if (version === null) errors.push("<overview> has no version attribute");
    else if (version.replace(/^ +| +$/g, "") !== "1") errors.push("version '" + version + "' is not supported (1 is)");
    if (!XML_WS.test(root.text)) errors.push("text directly inside <overview>");
    const seen = {};
    for (const child of root.children) {
        const c = resolve(child, r.scope, errors);
        const spec = c.ns === NAMESPACE ? ELEMENTS[c.local] : undefined;
        if (!spec) { errors.push("unknown element <" + child.name + ">"); continue; }
        if (seen[c.local]) { errors.push("<" + c.local + "> appears twice"); continue; }
        seen[c.local] = true;
        if (c.attrs.length) errors.push("attribute '" + c.attrs[0][0] + "' on <" + c.local + ">");
        if (child.children.length) { errors.push("<" + c.local + "> must hold text only"); continue; }
        const v = value(c.local, spec, child.text, errors);
        if (v !== undefined) config[spec[0]] = v;
    }
    if (errors.length) return { ok: false, config: freshDefaults(), errors: errors };
    return { ok: true, config: config, errors: [] };
}
