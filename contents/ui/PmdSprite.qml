import QtQuick

import "pokeapi.js" as Api

// Toca uma animação de uma folha de sprites do PMD Sprite Collab.
// As folhas de todas as animações usadas ficam carregadas, e só a atual aparece,
// assim trocar de animação não pisca.
Item {
    id: pmd

    property var pmdData: null       // resultado de Api.fetchPmd
    property bool shiny: false
    property string anim: "Idle"     // Walk | Idle | Sleep | Hop
    property int direction: 0        // linha da folha (Api.PMD_DIR)
    property bool loop: true
    property bool paused: false

    readonly property var anims: pmdData ? pmdData.anims : ({})
    readonly property string activeAnim: anims[anim] ? anim : (anims.Idle ? "Idle" : "Walk")
    readonly property var current: anims[activeAnim] || null
    // escala: Pokémon pequenos mantêm o tamanho relativo; grandes encolhem para caber
    readonly property real pixelScale: {
        const ref = anims.Walk || anims.Idle;
        if (!ref) return 1;
        // escala inteira: pixel art nítida e sem "vazar" o quadro vizinho na borda
        const raw = height / Math.max(32, ref.frameHeight);
        return raw >= 1 ? Math.round(raw) : raw;
    }
    readonly property bool loading: {
        const sheet = sheets.count > 0 ? sheets.itemAt(Api.PMD_ANIMS.indexOf(activeAnim)) : null;
        return !sheet || sheet.status !== Image.Ready;
    }
    property int frame: 0

    signal finished()                // fim de um ciclo quando loop = false
    signal sheetFailed(string name)  // folha não carregou nem depois das tentativas

    function hasAnim(name) { return !!anims[name]; }

    onActiveAnimChanged: { frame = 0; frameTimer.restart(); }
    onCurrentChanged: { frame = 0; frameTimer.restart(); }

    Timer {
        id: frameTimer
        running: pmd.current !== null && pmd.visible && !pmd.paused
        repeat: false
        // as durações do PMD estão em quadros a 60 fps
        interval: pmd.current ? Math.max(16, (pmd.current.durations[pmd.frame] || 4) * 1000 / 60) : 100
        onTriggered: {
            const n = pmd.current.durations.length;
            if (pmd.frame + 1 >= n) {
                if (!pmd.loop) { pmd.finished(); return; }
                pmd.frame = 0;
            } else {
                pmd.frame += 1;
            }
            restart();
        }
    }

    Repeater {
        id: sheets
        model: Api.PMD_ANIMS
        delegate: Item {
            id: sheet
            required property string modelData
            readonly property var info: pmd.anims[modelData] || null
            readonly property bool active: pmd.activeAnim === modelData && info !== null
            readonly property int rows: info && img.implicitHeight > 0
                ? Math.max(1, Math.round(img.implicitHeight / info.frameHeight)) : 1
            readonly property int status: img.status
            property bool useNormal: false   // sem versão shiny no SpriteCollab
            property int attempt: 0

            Connections {
                target: pmd
                function onShinyChanged() { sheet.useNormal = false; sheet.attempt = 0; }
            }

            visible: active && img.status === Image.Ready
            // tudo em pixels inteiros: com escala fracionada o quadro vizinho "vaza" na borda
            width: info ? Math.floor(info.frameWidth * pmd.pixelScale) : 0
            height: info ? Math.floor(info.frameHeight * pmd.pixelScale) : 0
            // o centro do quadro é o ponto de referência do PMD
            anchors.centerIn: parent
            // os pés ficam abaixo do centro do quadro; desce para encostar no chão
            anchors.verticalCenterOffset: pmd.height * 0.12
            clip: true

            Timer {
                id: retry
                interval: Api.retryDelay(sheet.attempt)
                // cada nova tentativa testa de novo a versão shiny e depois a normal
                onTriggered: { sheet.useNormal = false; sheet.attempt += 1; }
            }

            Image {
                id: img
                // o "?t=" muda a URL a cada tentativa para não reaproveitar o erro em cache
                source: sheet.info
                    ? Api.pmdFolder(pmd.pmdData.id, pmd.shiny && !sheet.useNormal) + sheet.info.file + "-Anim.png"
                      + (sheet.attempt > 0 ? "?t=" + sheet.attempt : "")
                    : ""
                smooth: false
                cache: true
                asynchronous: true
                width: implicitWidth * pmd.pixelScale
                height: implicitHeight * pmd.pixelScale
                x: sheet.active && sheet.info ? -Math.round(pmd.frame * sheet.info.frameWidth * pmd.pixelScale) : 0
                y: sheet.info ? -Math.round(Math.min(pmd.direction, sheet.rows - 1) * sheet.info.frameHeight * pmd.pixelScale) : 0
                onStatusChanged: {
                    if (status !== Image.Error) return;
                    if (pmd.shiny && !sheet.useNormal) sheet.useNormal = true;
                    else if (sheet.attempt < 3) retry.restart();
                    else pmd.sheetFailed(sheet.modelData);
                }
            }
        }
    }
}
