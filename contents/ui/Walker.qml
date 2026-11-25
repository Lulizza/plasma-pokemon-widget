import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "pokeapi.js" as Api

// Um Pokémon que busca seus dados na PokeAPI e vive dentro do item pai:
// fica parado, anda, às vezes dorme, e pula quando clicam nele.
// No estilo "pmd" usa as folhas animadas do PMD Sprite Collab (andar/parado/dormir/pular);
// nos outros estilos usa o sprite da PokeAPI espelhado e com uma balançadinha.
Item {
    id: walker

    property string pokemonName
    property string spriteStyle: "pmd"
    property bool shiny: false
    property bool walkEnabled: true
    property bool paused: false
    property int reloadToken: 0      // incrementar força recarregar
    property var memory: null        // objeto compartilhado para lembrar a posição entre recriações
    property real size: Kirigami.Units.gridUnit * 4
    property real depth: 0           // distância do chão (dá sensação de profundidade)
    property real restFraction: 0.5  // posição inicial / quando não anda (0 = esquerda, 1 = direita)
    property real speed: Kirigami.Units.gridUnit * 3  // px/s

    property var info: null
    property var pmdData: null
    property bool pmdBroken: false   // folhas PMD não carregaram → usa a PokeAPI
    property string error: ""        // "" | "notfound" | "network"
    property bool facingRight: false
    property string mode: "idle"     // idle | walk | sleep | hop
    property bool placed: false
    property int attempt: 0
    property int pmdAttempt: 0

    readonly property bool wantsPmd: spriteStyle === "pmd"
    readonly property bool pmdMode: wantsPmd && pmdData !== null && !pmdBroken
    readonly property bool alive: info !== null
    readonly property real maxX: Math.max(0, (parent ? parent.width : 0) - size)
    readonly property bool canWalk: walkEnabled && alive && maxX > 0
    readonly property bool loading: (!alive && error !== "notfound") || (sprite.item ? sprite.item.loading : false)

    signal clicked()

    width: size
    height: size
    y: (parent ? parent.height : 0) - height - depth
    z: -depth

    // --- dados ---------------------------------------------------------------

    function load() {
        const name = pokemonName;
        retryTimer.stop();
        if (!name) return;
        Api.fetchPokemon(name, function (err, data) {
            if (name !== walker.pokemonName) return;
            if (err) {
                walker.error = err;
                if (err === "network") {
                    retryTimer.interval = Api.retryDelay(walker.attempt++);
                    retryTimer.restart();
                }
                return;
            }
            walker.error = "";
            walker.attempt = 0;
            walker.info = data;
            walker.loadPmd();
        });
    }

    function loadPmd() {
        pmdRetryTimer.stop();
        if (!wantsPmd || !info || pmdData) return;
        const id = info.id;
        Api.fetchPmd(id, function (err, data) {
            if (!walker.info || walker.info.id !== id) return;
            if (err === "network") {
                pmdRetryTimer.interval = Api.retryDelay(walker.pmdAttempt++);
                pmdRetryTimer.restart();
                return;
            }
            walker.pmdData = data; // null se não houver sprites PMD → usa a PokeAPI
        });
    }

    function reload() {
        info = null;
        pmdData = null;
        pmdBroken = false;
        error = "";
        attempt = 0;
        pmdAttempt = 0;
        load();
    }

    Timer { id: retryTimer; onTriggered: walker.load() }
    Timer { id: pmdRetryTimer; onTriggered: walker.loadPmd() }

    onPokemonNameChanged: reload()
    onReloadTokenChanged: reload()
    onWantsPmdChanged: loadPmd()

    // --- comportamento -----------------------------------------------------

    function rest(ms) {
        walkAnim.stop();
        mode = "idle";
        think(ms);
    }

    function think(ms) {
        brain.interval = ms;
        if (paused) brain.stop(); else brain.restart();
    }

    function sleep() {
        walkAnim.stop();
        mode = "sleep";
        think(8000 + Math.random() * 12000);
    }

    function decide() {
        const r = Math.random();
        if (mode !== "sleep" && pmdMode && sprite.item && sprite.item.hasAnim("Sleep") && r < 0.12)
            sleep();
        else if (canWalk && r < 0.75)
            stepWalk();
        else
            rest(1500 + Math.random() * 3000);
    }

    function stepWalk() {
        let target = x;
        for (let i = 0; i < 5 && Math.abs(target - x) < size * 0.3; ++i)
            target = Math.random() * maxX;
        facingRight = target > x;
        mode = "walk";
        walkAnim.to = target;
        walkAnim.duration = Math.max(300, Math.abs(target - x) / speed * 1000);
        walkAnim.restart();
    }

    function poke() {
        if (mode === "sleep") {          // acorda
            rest(1200);
        } else if (pmdMode && sprite.item && sprite.item.hasAnim("Hop")) {
            walkAnim.stop();
            brain.stop();
            mode = "hop";                // PmdSprite avisa quando terminar
        } else {
            bounce.restart();
        }
        clicked();
    }

    // Posição inicial: onde estava antes (se a lista foi recriada) ou espalhado por restFraction.
    function place() {
        if (placed || maxX <= 0) return;
        const saved = memory ? memory[pokemonName] : undefined;
        if (walkEnabled) {
            x = saved ? Math.min(saved.x, maxX) : maxX * restFraction;
            facingRight = saved ? saved.facingRight : false;
        }
        placed = true;
    }

    function reset() {
        walkAnim.stop();
        brain.stop();
        mode = "idle";
        if (!walkEnabled) {
            x = Qt.binding(() => walker.maxX * walker.restFraction);
            facingRight = false;
        } else if (placed) {
            x = Math.min(x, maxX);
        }
        place();
        if (alive) think(300 + Math.random() * 2000); // cada um começa num tempo diferente
    }

    onAliveChanged: reset()
    onWalkEnabledChanged: reset()
    onMaxXChanged: {
        if (!placed) { place(); return; }
        if (walkEnabled && x > maxX) {
            if (mode === "walk") rest(500);
            x = maxX;
        }
    }
    onPausedChanged: {
        if (paused) {
            brain.stop();
            if (walkAnim.running) walkAnim.pause();
        } else if (walkAnim.paused) {
            walkAnim.resume();
        } else if (alive && mode !== "hop") {
            think(300 + Math.random() * 1000);
        }
    }
    Component.onCompleted: { reload(); reset(); }
    Component.onDestruction: {
        if (memory && placed && pokemonName)
            memory[pokemonName] = { x: x, facingRight: facingRight };
    }

    Timer {
        id: brain
        onTriggered: walker.decide()
    }

    NumberAnimation {
        id: walkAnim
        target: walker
        property: "x"
        easing.type: walker.pmdMode ? Easing.Linear : Easing.InOutSine
        onFinished: if (walker.mode === "walk") walker.rest(1000 + Math.random() * 3000)
    }

    // --- desenho -------------------------------------------------------------

    Loader {
        id: sprite
        anchors.fill: parent
        active: walker.alive
        sourceComponent: walker.pmdMode ? pmdComponent : apiComponent
    }

    Component {
        id: pmdComponent
        PmdSprite {
            pmdData: walker.pmdData
            shiny: walker.shiny
            paused: walker.paused
            anim: walker.mode === "walk" ? "Walk"
                : walker.mode === "sleep" ? "Sleep"
                : walker.mode === "hop" ? "Hop" : "Idle"
            loop: walker.mode !== "hop"
            direction: walker.mode === "walk"
                ? (walker.facingRight ? Api.PMD_DIR.right : Api.PMD_DIR.left)
                : Api.PMD_DIR.down
            onFinished: walker.rest(800 + Math.random() * 1500)
            onSheetFailed: name => {
                if (name === "Idle" || name === "Walk") walker.pmdBroken = true;
                else if (walker.mode === "hop" || walker.mode === "sleep") walker.rest(1000);
            }
        }
    }

    Component {
        id: apiComponent
        PokemonSprite {
            id: apiSprite
            source: Api.spriteUrl(walker.info, walker.spriteStyle, walker.shiny)
            pixelated: Api.isPixelStyle(walker.spriteStyle)
            paused: walker.paused
            transform: [
                // os sprites olham para a esquerda; espelha ao andar para a direita
                Scale {
                    origin.x: apiSprite.width / 2
                    xScale: walker.facingRight ? -1 : 1
                },
                Translate { y: bob.y }
            ]
        }
    }

    // balançadinha ao andar (só nos sprites da PokeAPI, o PMD já tem animação de andar)
    QtObject { id: bob; property real y: 0 }
    SequentialAnimation {
        running: walkAnim.running && !walkAnim.paused && !walker.pmdMode
        loops: Animation.Infinite
        onRunningChanged: if (!running) bob.y = 0
        NumberAnimation { target: bob; property: "y"; to: -walker.size * 0.04; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: bob; property: "y"; to: 0; duration: 160; easing.type: Easing.InQuad }
    }

    // pulinho simples para quem não tem animação "Hop"
    transform: Translate { id: hop }
    SequentialAnimation {
        id: bounce
        NumberAnimation { target: hop; property: "y"; to: -Kirigami.Units.gridUnit; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: hop; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBounce }
    }

    // "Zz" quando está dormindo
    Text {
        visible: walker.mode === "sleep"
        text: "z<sup>z</sup>"
        textFormat: Text.StyledText
        color: "white"
        style: Text.Outline
        styleColor: "#40000000"
        font.bold: true
        font.pixelSize: Math.max(10, walker.size * 0.16)
        anchors.right: parent.right
        anchors.rightMargin: walker.size * 0.15
        y: walker.size * 0.2
        SequentialAnimation on opacity {
            running: walker.mode === "sleep" && !walker.paused
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 600 }
            PauseAnimation { duration: 900 }
            NumberAnimation { to: 0; duration: 600 }
        }
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        width: Math.min(Kirigami.Units.iconSizes.medium, walker.size * 0.5)
        height: width
        visible: walker.loading && walker.error === ""
        running: visible && !walker.paused
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Math.min(Kirigami.Units.iconSizes.medium, walker.size * 0.5)
        height: width
        visible: walker.error !== ""
        // sem rede: ícone de desconectado (vai tentar de novo); não existe: aviso
        source: walker.error === "network" ? "network-disconnect" : "dialog-warning"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: walker.alive ? walker.poke() : walker.reload()
    }
}
