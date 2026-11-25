.pragma library

// Cliente da PokeAPI (https://pokeapi.co) e do PMD Sprite Collab, com:
//  - cache em memória compartilhado por todos que importam este arquivo;
//  - cache persistente (exportCache/importCache) para funcionar no login sem rede;
//  - limite de tempo nas requisições (o XMLHttpRequest do QML não tem timeout);
//  - GraphQL para baixar só os campos usados (~20 KB em vez de ~500 KB), com REST de reserva.

var GRAPHQL = "https://graphql.pokeapi.co/v1beta2";
var REST = "https://pokeapi.co/api/v2/";
var MAX_ID = 1025;
var TIMEOUT_MS = 15000;

var typeColors = {
    normal: "#A8A77A", fire: "#EE8130", water: "#6390F0", electric: "#F7D02C",
    grass: "#7AC74C", ice: "#96D9D6", fighting: "#C22E28", poison: "#A33EA1",
    ground: "#E2BF65", flying: "#A98FF3", psychic: "#F95587", bug: "#A6B91A",
    rock: "#B6A136", ghost: "#735797", dragon: "#6F35FC", dark: "#705746",
    steel: "#B7B7CE", fairy: "#D685AD"
};

// ---------------------------------------------------------------------------
// Infraestrutura: timers, requisições com timeout, tentativas
// ---------------------------------------------------------------------------

var host = null;  // objeto QML usado como pai dos Timers

// Precisa ser chamado uma vez (pelo widget ou pela página de configuração).
function setHost(obj) {
    if (!host) host = obj;
}

function delay(ms, fn) {
    if (!host) return null;
    try {
        var t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", host);
        t.interval = ms;
        t.triggered.connect(function () { fn(); t.destroy(); });
        t.start();
        return t;
    } catch (e) {
        return null;
    }
}

// callback(status, texto). status 0 = falha de rede ou tempo esgotado.
function request(method, url, body, callback) {
    var xhr = new XMLHttpRequest();
    var done = false;
    var timer = null;
    function finish(status, text) {
        if (done) return;
        done = true;
        if (timer) { timer.stop(); timer.destroy(); timer = null; }
        callback(status, text);
    }
    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) finish(xhr.status, xhr.responseText);
    };
    xhr.open(method, url);
    if (body) xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(body || null);
    timer = delay(TIMEOUT_MS, function () {
        timer = null;
        finish(0, "");
        try { xhr.abort(); } catch (e) { }
    });
}

// Espera para a n-ésima nova tentativa: 5s, 15s, 45s, 2min15s, depois 5min.
function retryDelay(attempt) {
    return Math.min(5000 * Math.pow(3, attempt), 300000);
}

// ---------------------------------------------------------------------------
// Nomes
// ---------------------------------------------------------------------------

// "Mr. Mime" → "mr-mime", "Nidoran♀" → "nidoran-f", "Farfetch'd" → "farfetchd", "Flabébé" → "flabebe"
function normalize(name) {
    var s = String(name).trim().toLowerCase();
    if (s.normalize) s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    return s.replace(/♀/g, "-f").replace(/♂/g, "-m")
            .replace(/[.'’:]/g, "")
            .replace(/[\s_]+/g, "-")
            .replace(/-+/g, "-")
            .replace(/^-|-$/g, "");
}

function displayName(name) {
    return String(name).split("-").map(function (p) {
        return p.charAt(0).toUpperCase() + p.slice(1);
    }).join(" ");
}

function errorText(err) {
    switch (err) {
    case "notfound": return "Pokémon não encontrado";
    case "network": return "Sem conexão com a PokeAPI";
    case "empty": return "Digite um nome ou número";
    }
    return "Erro desconhecido";
}

// ---------------------------------------------------------------------------
// Cache (memória + persistente)
// ---------------------------------------------------------------------------

var cache = {};      // nome canônico → dados
var aliases = {};    // busca normalizada ("25", "giratina") → nome canônico
var pending = {};    // busca → [callbacks]
var pmdCache = {};   // id → dados PMD | null (não existe)
var pmdPending = {};

var persistHook = null;
var persistTimer = null;

// fn() é chamada (com atraso, agrupando mudanças) sempre que algo novo entra no cache.
function setPersistHook(fn) { persistHook = fn; }

function schedulePersist() {
    if (persistTimer || !persistHook) return;
    persistTimer = delay(2000, function () {
        persistTimer = null;
        if (persistHook) persistHook();
    });
}

function lookup(key) {
    return cache[aliases[key] || key] || null;
}

function remember(key, data) {
    cache[data.name] = data;
    aliases[key] = data.name;
    aliases[String(data.id)] = data.name;
    schedulePersist();
}

// Esquece o que se sabe sobre esses nomes, para forçar um download novo.
function forget(names) {
    for (var i = 0; i < names.length; ++i) {
        var key = normalize(names[i]);
        var data = lookup(key);
        if (data) {
            delete pmdCache[data.id];
            for (var a in aliases) if (aliases[a] === data.name) delete aliases[a];
            delete cache[data.name];
        }
        delete aliases[key];
    }
    schedulePersist();
}

// Serializa só o necessário para os Pokémon em `keepNames`.
function exportCache(keepNames) {
    var out = { v: 1, p: {}, a: {}, m: {} };
    for (var i = 0; i < keepNames.length; ++i) {
        var data = lookup(normalize(keepNames[i]));
        if (!data) continue;
        out.p[data.name] = data;
        if (pmdCache[data.id] !== undefined) out.m[data.id] = pmdCache[data.id];
    }
    for (var a in aliases) if (out.p[aliases[a]]) out.a[a] = aliases[a];
    return JSON.stringify(out);
}

// Revalida dados PMD vindos do cache salvo. null = "não tem PMD".
function validPmd(d, id) {
    if (!d || !d.anims || !(id > 0)) return null;
    var anims = {};
    for (var i = 0; i < PMD_ANIMS.length; ++i) {
        var a = d.anims[PMD_ANIMS[i]];
        if (!a || !/^[A-Za-z]+$/.test(a.file)) continue;
        if (!(a.frameWidth > 0 && a.frameWidth <= 512 && a.frameHeight > 0 && a.frameHeight <= 512)) continue;
        if (!Array.isArray(a.durations) || a.durations.length === 0) continue;
        anims[PMD_ANIMS[i]] = {
            file: a.file, frameWidth: a.frameWidth, frameHeight: a.frameHeight,
            durations: a.durations.slice(0, 64).map(function (x) { return Math.min(Math.max(parseInt(x) || 1, 1), 600); })
        };
    }
    return (anims.Walk || anims.Idle) ? { id: id, anims: anims } : null;
}

function unpick(s) {
    return s ? { front_default: s.normal, front_shiny: s.shiny } : {};
}

function importCache(json) {
    if (!json) return;
    try {
        var obj = JSON.parse(json);
        if (obj.v !== 1) return;
        var k;
        for (k in obj.p) {
            var e = obj.p[k];
            if (cache[k] || !e || typeof e.name !== "string" || !(e.id > 0)) continue;
            cache[k] = {
                id: e.id,
                name: e.name,
                types: Array.isArray(e.types) ? e.types.filter(function (t) { return typeof t === "string"; }) : [],
                sprites: pickSprites({
                    front_default: e.sprites && e.sprites["default"] && e.sprites["default"].normal,
                    front_shiny: e.sprites && e.sprites["default"] && e.sprites["default"].shiny,
                    other: {
                        showdown: unpick(e.sprites && e.sprites.animated),
                        "official-artwork": unpick(e.sprites && e.sprites.artwork),
                        home: unpick(e.sprites && e.sprites.home)
                    }
                })
            };
        }
        for (k in obj.a) if (!aliases[k]) aliases[k] = obj.a[k];
        for (k in obj.m) if (pmdCache[k] === undefined) pmdCache[k] = validPmd(obj.m[k], parseInt(k));
    } catch (e) { /* cache corrompido: ignora */ }
}

// ---------------------------------------------------------------------------
// PokeAPI
// ---------------------------------------------------------------------------

function pickSprites(spr) {
    if (typeof spr === "string") {
        try { spr = JSON.parse(spr); } catch (e) { spr = {}; }
    }
    spr = spr || {};
    var other = spr.other || {};
    // só aceita https:// (dados vindos da rede ou do cache salvo viram fonte de imagem)
    function safe(url) {
        return typeof url === "string" && /^https:\/\/[^\s"'<>]+$/.test(url) ? url : "";
    }
    function pick(obj) {
        obj = obj || {};
        return { normal: safe(obj.front_default), shiny: safe(obj.front_shiny) };
    }
    return {
        "default": pick(spr),
        animated: pick(other.showdown),
        artwork: pick(other["official-artwork"]),
        home: pick(other.home)
    };
}

var GQL_QUERY =
    "query($n:String!,$id:Int!){" +
    " byName: pokemon(where:{name:{_eq:$n}}){...F}" +
    " byId: pokemon(where:{id:{_eq:$id}}){...F}" +
    " species: pokemonspecies(where:{name:{_eq:$n}}){ pokemons(where:{is_default:{_eq:true}}){...F} }" +
    "} fragment F on pokemon { id name pokemontypes(order_by:{slot:asc}){ type{ name } } pokemonsprites{ sprites } }";

// callback(erro, dados|null). erro: null | "notfound" | "network"
function fetchGraphQL(key, callback) {
    var numeric = /^\d+$/.test(key);
    var body = JSON.stringify({
        query: GQL_QUERY,
        variables: { n: numeric ? "" : key, id: numeric ? parseInt(key) : -1 }
    });
    request("POST", GRAPHQL, body, function (status, text) {
        if (status !== 200) { callback("network", null); return; }
        try {
            var res = JSON.parse(text);
            if (res.errors || !res.data) { callback("network", null); return; }
            var d = res.data;
            var p = d.byName[0] || d.byId[0]
                || (d.species[0] && d.species[0].pokemons[0]) || null;
            if (!p) { callback("notfound", null); return; }
            callback(null, {
                id: p.id,
                name: p.name,
                types: p.pokemontypes.map(function (t) { return t.type.name; }),
                sprites: pickSprites(p.pokemonsprites[0] ? p.pokemonsprites[0].sprites : {})
            });
        } catch (e) {
            callback("network", null);
        }
    });
}

// Reserva caso o GraphQL (beta) saia do ar: /pokemon/{x}, e no 404 tenta /pokemon-species/{x}.
function fetchRest(key, callback, viaSpecies) {
    request("GET", REST + "pokemon/" + encodeURIComponent(key), null, function (status, text) {
        if (status === 200) {
            try {
                var j = JSON.parse(text);
                callback(null, {
                    id: j.id,
                    name: j.name,
                    types: (j.types || []).map(function (t) { return t.type.name; }),
                    sprites: pickSprites(j.sprites)
                });
            } catch (e) { callback("network", null); }
            return;
        }
        if (status !== 404) { callback("network", null); return; }
        if (viaSpecies) { callback("notfound", null); return; }
        request("GET", REST + "pokemon-species/" + encodeURIComponent(key), null, function (s2, t2) {
            if (s2 === 404) { callback("notfound", null); return; }
            if (s2 !== 200) { callback("network", null); return; }
            try {
                var v = JSON.parse(t2).varieties.filter(function (x) { return x.is_default; })[0];
                if (!v) { callback("notfound", null); return; }
                fetchRest(v.pokemon.name, callback, true);
            } catch (e) { callback("network", null); }
        });
    });
}

// callback(erro, dados) — erro: null | "empty" | "notfound" | "network"
function fetchPokemon(name, callback) {
    var key = normalize(name);
    if (!key) { callback("empty", null); return; }
    var hit = lookup(key);
    if (hit) { callback(null, hit); return; }
    if (pending[key]) { pending[key].push(callback); return; }
    pending[key] = [callback];

    function deliver(err, data) {
        var cbs = pending[key] || [];
        delete pending[key];
        if (data) remember(key, data);
        for (var i = 0; i < cbs.length; ++i) {
            try { cbs[i](err, data); } catch (e) { /* objeto QML destruído */ }
        }
    }

    fetchGraphQL(key, function (err, data) {
        if (err === "network") fetchRest(key, deliver);
        else deliver(err, data);
    });
}

// Retorna a URL do sprite no estilo pedido, caindo para o sprite padrão se não existir.
function spriteUrl(data, style, shiny) {
    if (!data) return "";
    if (style === "pmd") style = "animated"; // fora do palco (painel, configurações) usa o GIF
    var order = [style, "default", "artwork"];
    for (var i = 0; i < order.length; ++i) {
        var s = data.sprites[order[i]];
        if (!s) continue;
        var url = shiny ? (s.shiny || s.normal) : s.normal;
        if (url) return url;
    }
    return "";
}

function isPixelStyle(style) {
    return style === "default" || style === "animated" || style === "pmd";
}

// ---------------------------------------------------------------------------
// Sprites animados estilo Pokémon Mystery Dungeon (PMD Sprite Collab)
// https://github.com/PMDCollab/SpriteCollab — licença CC BY-NC 4.0
// Cada animação é uma folha PNG: colunas = quadros, linhas = 8 direções
// (0 baixo, 1 baixo-dir, 2 dir, 3 cima-dir, 4 cima, 5 cima-esq, 6 esq, 7 baixo-esq).
// ---------------------------------------------------------------------------

var PMD_BASE = "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite/";
var PMD_DIR = { down: 0, right: 2, left: 6 };
var PMD_ANIMS = ["Walk", "Idle", "Sleep", "Hop"];  // só o que o widget usa

function pad4(n) {
    var s = String(n);
    while (s.length < 4) s = "0" + s;
    return s;
}

function pmdFolder(id, shiny) {
    return PMD_BASE + pad4(parseInt(id)) + "/" + (shiny ? "0000/0001/" : "");
}

function xmlTag(block, tag) {
    var m = block.match(new RegExp("<" + tag + ">([^<]*)</" + tag + ">"));
    return m ? m[1].trim() : "";
}

function parseAnimData(xml) {
    var all = {};
    var re = /<Anim>([\s\S]*?)<\/Anim>/g;
    var m;
    while ((m = re.exec(xml)) !== null) {
        var block = m[1];
        var name = xmlTag(block, "Name");
        if (!name) continue;
        var copyOf = xmlTag(block, "CopyOf");
        if (copyOf) { all[name] = { copyOf: copyOf }; continue; }
        var durations = [];
        var dr = /<Duration>(\d+)<\/Duration>/g, d;
        while ((d = dr.exec(block)) !== null && durations.length < 64)
            durations.push(Math.min(Math.max(parseInt(d[1]), 1), 600));
        var fw = parseInt(xmlTag(block, "FrameWidth"));
        var fh = parseInt(xmlTag(block, "FrameHeight"));
        // ignora animações com dimensões inválidas (evita divisão por zero / folhas absurdas)
        if (!(fw > 0 && fw <= 512 && fh > 0 && fh <= 512)) continue;
        all[name] = { file: name, frameWidth: fw, frameHeight: fh, durations: durations };
    }
    // fica só com as animações usadas, resolvendo <CopyOf>
    var anims = {};
    for (var i = 0; i < PMD_ANIMS.length; ++i) {
        var a = all[PMD_ANIMS[i]];
        if (a && a.copyOf) a = all[a.copyOf];
        if (a && !a.copyOf && a.durations.length > 0) anims[PMD_ANIMS[i]] = a;
    }
    return anims;
}

// callback(erro, { id, anims }) — erro: "notfound" (não tem sprites PMD) | "network"
function fetchPmd(id, callback) {
    if (!(id > 0 && id < 10000)) { callback("notfound", null); return; }
    if (pmdCache[id] !== undefined) {
        if (pmdCache[id]) callback(null, pmdCache[id]); else callback("notfound", null);
        return;
    }
    if (pmdPending[id]) { pmdPending[id].push(callback); return; }
    pmdPending[id] = [callback];

    request("GET", PMD_BASE + pad4(id) + "/AnimData.xml", null, function (status, text) {
        var cbs = pmdPending[id] || [];
        delete pmdPending[id];
        var data = null, err = null;
        if (status === 200) {
            var anims = parseAnimData(text);
            if (anims.Walk || anims.Idle) data = { id: id, anims: anims };
            else err = "notfound";
        } else {
            err = status === 404 ? "notfound" : "network";
        }
        // "não existe" só é guardado quando o servidor respondeu; erro de rede tenta de novo depois
        if (err !== "network") { pmdCache[id] = data; schedulePersist(); }
        for (var i = 0; i < cbs.length; ++i) {
            try { cbs[i](err, data); } catch (e) { }
        }
    });
}
