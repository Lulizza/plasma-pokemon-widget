import QtQuick

import "pokeapi.js" as Api

// Mostra um sprite remoto. GIFs (estilo Showdown) usam AnimatedImage.
// Se a imagem falhar (ex.: sem rede no login), tenta de novo com espera crescente.
Item {
    id: sprite

    property url source
    property bool pixelated: true
    property bool paused: false
    readonly property bool isGif: source.toString().toLowerCase().endsWith(".gif")
    readonly property bool loading: active && (!loader.item || loader.item.status === Image.Loading)
    readonly property bool failed: loader.item ? loader.item.status === Image.Error : false
    readonly property bool active: source.toString() !== ""

    property int attempt: 0
    // o "?t=" muda a URL a cada tentativa para não reaproveitar o erro em cache
    readonly property url effectiveSource: active && attempt > 0
        ? source.toString() + "?t=" + attempt : source

    onSourceChanged: attempt = 0

    Timer {
        id: retry
        interval: Api.retryDelay(sprite.attempt)
        onTriggered: sprite.attempt += 1
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: sprite.active
        sourceComponent: sprite.isGif ? animatedComponent : staticComponent
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (loader.item.status === Image.Error && sprite.attempt < 5) retry.restart();
        }
    }

    Component {
        id: staticComponent
        Image {
            source: sprite.effectiveSource
            fillMode: Image.PreserveAspectFit
            smooth: !sprite.pixelated
            mipmap: !sprite.pixelated
            asynchronous: true
            cache: true
        }
    }

    Component {
        id: animatedComponent
        AnimatedImage {
            source: sprite.effectiveSource
            fillMode: Image.PreserveAspectFit
            smooth: !sprite.pixelated
            playing: sprite.visible && !sprite.paused
            cache: true
        }
    }
}
