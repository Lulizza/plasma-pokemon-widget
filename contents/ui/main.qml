import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "pokeapi.js" as Api

PlasmoidItem {
    id: root

    readonly property var pokemonList: Plasmoid.configuration.pokemonList
    readonly property int count: pokemonList ? pokemonList.length : 0
    readonly property int activeIndex: count > 0
        ? Math.max(0, Math.min(Plasmoid.configuration.activeIndex, count - 1)) : 0
    readonly property string currentName: count > 0 ? pokemonList[activeIndex] : ""

    readonly property string spriteStyle: Plasmoid.configuration.spriteStyle
    readonly property var shinyList: Plasmoid.configuration.shinyList
    readonly property bool shiny: isShiny(currentName)

    property var pokemon: null
    property string error: ""
    property string errorCode: ""    // "" | "notfound" | "network"
    property bool loading: false
    property int attempt: 0
    property int reloadToken: 0
    property var credits: null       // artistas do sprite PMD do selecionado
    readonly property string creditText: spriteStyle === "pmd" ? Api.creditText(credits, shiny) : ""
    // posições dos Pokémon, para não voltarem ao início quando a lista é recriada
    property var walkerMemory: ({})

    readonly property bool onDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // Pausa as animações quando ninguém pode vê-las: popup fechado no painel,
    // ou janela maximizada/tela cheia cobrindo a área de trabalho.
    readonly property bool paused: (inPanel && !root.expanded)
        || (coverage.item !== null && coverage.item.covered)

    readonly property string spriteUrl: Api.spriteUrl(pokemon, spriteStyle, shiny)
    readonly property string prettyName: pokemon ? Api.displayName(pokemon.name) : Api.displayName(currentName)

    switchWidth: Kirigami.Units.gridUnit * 8
    switchHeight: Kirigami.Units.gridUnit * 8

    toolTipMainText: pokemon ? prettyName + (shiny ? " ✨" : "") : i18n("Pokémon")
    // dados da API nunca são interpretados como HTML
    toolTipTextFormat: Text.PlainText
    toolTipSubText: pokemon
        ? "#" + pokemon.id + " · " + pokemon.types.map(t => Api.displayName(t)).join(" / ")
          + (creditText ? "\n" + i18n("Sprite: %1 (PMD Sprite Collab)", creditText) : "")
        : (error || "")

    Plasmoid.icon: "applications-games"
    // fundo transparente por padrão; dá para trocar no modo de edição
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    onCurrentNameChanged: { attempt = 0; load(); }
    onPokemonListChanged: Api.schedulePersist() // tira do cache quem saiu da lista
    Component.onCompleted: {
        // migração: a antiga opção "shiny" valia para todos
        if (Plasmoid.configuration.shiny) {
            Plasmoid.configuration.shinyList = Array.from(pokemonList);
            Plasmoid.configuration.shiny = false;
        }
        Api.setHost(root);
        Api.importCache(Plasmoid.configuration.cache);
        Api.setPersistHook(() => {
            const json = Api.exportCache(root.pokemonList);
            if (json !== Plasmoid.configuration.cache) Plasmoid.configuration.cache = json;
        });
        load();
    }

    function isShiny(name) {
        return !!shinyList && shinyList.indexOf(name) !== -1;
    }

    function loadCredits() {
        const id = pokemon ? pokemon.id : 0;
        if (!id || spriteStyle !== "pmd") { credits = null; return; }
        Api.fetchCredits(id, function (err, data) {
            if (root.pokemon && root.pokemon.id === id) root.credits = data;
        });
    }
    onPokemonChanged: loadCredits()
    onSpriteStyleChanged: loadCredits()

    function load() {
        retryTimer.stop();
        const name = currentName;
        if (!name) {
            pokemon = null;
            loading = false;
            error = i18n("Nenhum Pokémon configurado");
            errorCode = "";
            return;
        }
        loading = true;
        error = "";
        errorCode = "";
        Api.fetchPokemon(name, function (err, data) {
            if (name !== root.currentName) return; // trocou no meio do caminho
            root.loading = false;
            if (err) {
                root.pokemon = null;
                root.error = Api.errorText(err);
                root.errorCode = err;
                if (err === "network") {
                    retryTimer.interval = Api.retryDelay(root.attempt++);
                    retryTimer.restart();
                }
            } else {
                root.attempt = 0;
                root.pokemon = data;
            }
        });
    }

    // Esquece o cache dos Pokémon da lista e baixa tudo de novo.
    function reloadAll() {
        Api.forget(pokemonList);
        attempt = 0;
        pokemon = null;
        load();
        reloadToken += 1;
    }

    function select(i) {
        if (count === 0) return;
        const idx = ((i % count) + count) % count;
        if (idx !== Plasmoid.configuration.activeIndex) Plasmoid.configuration.activeIndex = idx;
    }
    function next() { select(activeIndex + 1); }
    function previous() { select(activeIndex - 1); }

    Timer { id: retryTimer; onTriggered: root.load() }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.cycleInterval) * 60 * 1000
        running: Plasmoid.configuration.cycleInterval > 0 && root.count > 1
        repeat: true
        onTriggered: root.next()
    }

    // Detecta janelas maximizadas/tela cheia nesta tela, área de trabalho virtual e atividade.
    // Só existe quando o widget está na área de trabalho e a opção está ligada.
    Loader {
        id: coverage
        active: root.onDesktop && Plasmoid.configuration.pauseWhenCovered
        sourceComponent: Item {
            id: coverageItem
            property bool covered: false

            function update() {
                for (let i = 0; i < tasks.count; ++i) {
                    const idx = tasks.index(i, 0);
                    if (tasks.data(idx, TaskManager.AbstractTasksModel.IsMinimized)) continue;
                    if (tasks.data(idx, TaskManager.AbstractTasksModel.IsMaximized)
                        || tasks.data(idx, TaskManager.AbstractTasksModel.IsFullScreen)) {
                        covered = true;
                        return;
                    }
                }
                covered = false;
            }

            TaskManager.VirtualDesktopInfo { id: desktopInfo }
            TaskManager.ActivityInfo { id: activityInfo }
            TaskManager.TasksModel {
                id: tasks
                groupMode: TaskManager.TasksModel.GroupDisabled
                sortMode: TaskManager.TasksModel.SortDisabled
                screenGeometry: Plasmoid.containment.screenGeometry
                virtualDesktop: desktopInfo.currentDesktop
                activity: activityInfo.currentActivity
                filterByScreen: true
                filterByVirtualDesktop: true
                filterByActivity: true
                onCountChanged: coverageItem.update()
                onDataChanged: coverageItem.update()
                onModelReset: coverageItem.update()
            }
            Component.onCompleted: update()
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Pokémon anterior")
            icon.name: "go-previous"
            enabled: root.count > 1
            onTriggered: root.previous()
        },
        PlasmaCore.Action {
            text: i18n("Próximo Pokémon")
            icon.name: "go-next"
            enabled: root.count > 1
            onTriggered: root.next()
        },
        PlasmaCore.Action {
            text: i18n("Recarregar")
            icon.name: "view-refresh"
            onTriggered: root.reloadAll()
        }
    ]

    // No painel: só o sprite. Clique abre o popup, rodinha troca de Pokémon.
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) root.next();
            else root.expanded = !root.expanded;
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) root.previous();
            else if (wheel.angleDelta.y < 0) root.next();
        }

        PokemonSprite {
            anchors.fill: parent
            source: root.spriteUrl
            pixelated: Api.isPixelStyle(root.spriteStyle)
        }
        Kirigami.Icon {
            anchors.fill: parent
            visible: !root.pokemon
            source: root.error ? "dialog-warning" : "applications-games"
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16
        Layout.minimumWidth: Kirigami.Units.gridUnit * 8
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8

        // Mensagem cheia só quando não há o que mostrar no palco:
        // lista vazia, ou o único Pokémon não existe na PokeAPI.
        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: !stage.visible
            iconName: root.count > 0 ? "dialog-warning" : "applications-games"
            text: root.error
            helpfulAction: QQC2.Action {
                text: i18n("Configurar…")
                icon.name: "configure"
                onTriggered: Plasmoid.internalAction("configure").trigger()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            MouseArea {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                clip: true
                visible: root.count > 0
                    && (showAll || root.pokemon !== null || root.loading || root.errorCode !== "notfound")

                readonly property bool showAll: Plasmoid.configuration.showAll && root.count > 1
                readonly property bool walk: Plasmoid.configuration.walk
                readonly property real spriteSize: showAll
                    ? Math.min(height * 0.85, width / Math.max(1.5, root.count * 0.7))
                    : Math.min(height, width * (walk ? 0.6 : 1))

                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0) root.previous();
                    else if (wheel.angleDelta.y < 0) root.next();
                }

                Repeater {
                    model: stage.showAll ? root.pokemonList : [root.currentName]
                    delegate: Walker {
                        required property int index
                        required property string modelData
                        pokemonName: modelData
                        spriteStyle: root.spriteStyle
                        shiny: root.isShiny(modelData)
                        walkEnabled: stage.walk
                        paused: root.paused
                        reloadToken: root.reloadToken
                        memory: root.walkerMemory
                        size: stage.spriteSize
                        depth: stage.showAll ? (index % 3) * stage.height * 0.07 : 0
                        restFraction: stage.showAll ? (index + 0.5) / root.count : 0.5
                        onClicked: if (stage.showAll) root.select(index)
                    }
                }
            }

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                visible: Plasmoid.configuration.showName && root.pokemon !== null
                level: 3
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.pokemon
                    ? "#" + String(root.pokemon.id).padStart(3, "0") + " " + root.prettyName + (root.shiny ? " ✨" : "")
                    : ""
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                visible: Plasmoid.configuration.showName && root.pokemon !== null
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: root.pokemon ? root.pokemon.types : []
                    delegate: Rectangle {
                        required property string modelData
                        width: typeLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: typeLabel.implicitHeight + Kirigami.Units.smallSpacing
                        radius: height / 2
                        color: Api.typeColors[modelData] || Kirigami.Theme.highlightColor
                        PlasmaComponents3.Label {
                            id: typeLabel
                            anchors.centerIn: parent
                            text: Api.displayName(parent.modelData)
                            textFormat: Text.PlainText
                            color: "white"
                            font.bold: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: Plasmoid.configuration.showName && root.creditText !== ""
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                text: i18n("Sprite: %1", root.creditText)
            }
        }
    }
}
