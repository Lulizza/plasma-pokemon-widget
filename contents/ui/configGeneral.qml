import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "pokeapi.js" as Api

KCM.SimpleKCM {
    id: page

    property var cfg_pokemonList: []
    property int cfg_activeIndex: 0
    property string cfg_spriteStyle: "pmd"
    property var cfg_shinyList: []
    property bool cfg_showName: true
    property int cfg_cycleInterval: 0
    property bool cfg_walk: true
    property bool cfg_walkDefault
    property bool cfg_showAll: true
    property bool cfg_showAllDefault
    property bool cfg_pauseWhenCovered: true
    property bool cfg_pauseWhenCoveredDefault

    property var cfg_pokemonListDefault
    property int cfg_activeIndexDefault
    property string cfg_spriteStyleDefault
    property var cfg_shinyListDefault
    property bool cfg_showNameDefault
    property int cfg_cycleIntervalDefault

    property bool busy: false
    property string addError: ""

    function listCopy() {
        const out = [];
        for (let i = 0; i < cfg_pokemonList.length; ++i) out.push(cfg_pokemonList[i]);
        return out;
    }

    Component.onCompleted: Api.setHost(page)

    function addPokemon(query) {
        addError = "";
        busy = true;
        Api.fetchPokemon(query, function (err, data) {
            page.busy = false;
            if (err) {
                page.addError = Api.errorText(err);
                return;
            }
            const list = page.listCopy();
            if (list.indexOf(data.name) !== -1) {
                page.addError = i18n("%1 já está na lista", Api.displayName(data.name));
                return;
            }
            list.push(data.name);
            page.cfg_pokemonList = list;
            if (list.length === 1) page.cfg_activeIndex = 0;
            nameField.text = "";
        });
    }

    function isShiny(name) {
        return cfg_shinyList.indexOf(name) !== -1;
    }

    function setShiny(name, on) {
        const list = Array.from(cfg_shinyList).filter(n => n !== name);
        if (on) list.push(name);
        cfg_shinyList = list;
    }

    function removeAt(i) {
        const list = listCopy();
        setShiny(list[i], false);
        list.splice(i, 1);
        if (cfg_activeIndex > i || cfg_activeIndex >= list.length)
            cfg_activeIndex = Math.max(0, cfg_activeIndex - 1);
        cfg_pokemonList = list;
    }

    function move(i, delta) {
        const j = i + delta;
        const list = listCopy();
        if (j < 0 || j >= list.length) return;
        const tmp = list[i]; list[i] = list[j]; list[j] = tmp;
        if (cfg_activeIndex === i) cfg_activeIndex = j;
        else if (cfg_activeIndex === j) cfg_activeIndex = i;
        cfg_pokemonList = list;
    }

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Adicionar Pokémon:")
            QQC2.TextField {
                id: nameField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                placeholderText: i18n("nome ou número (ex: eevee, 133)")
                enabled: !page.busy
                onAccepted: if (text.trim() !== "") page.addPokemon(text)
            }
            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Adicionar")
                enabled: !page.busy && nameField.text.trim() !== ""
                onClicked: page.addPokemon(nameField.text)
            }
            QQC2.Button {
                icon.name: "roll"
                text: i18n("Aleatório")
                enabled: !page.busy
                onClicked: page.addPokemon(String(1 + Math.floor(Math.random() * Api.MAX_ID)))
            }
            QQC2.BusyIndicator {
                visible: page.busy
                running: visible
                Layout.preferredHeight: nameField.implicitHeight
                Layout.preferredWidth: nameField.implicitHeight
            }
        }

        QQC2.Label {
            visible: page.addError !== ""
            text: page.addError
            textFormat: Text.PlainText
            color: Kirigami.Theme.negativeTextColor
        }

        QQC2.ButtonGroup { id: activeGroup }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Meus Pokémon:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            spacing: 0

            QQC2.Label {
                visible: page.cfg_pokemonList.length === 0
                text: i18n("Nenhum Pokémon adicionado ainda.")
                opacity: 0.7
            }

            Repeater {
                model: page.cfg_pokemonList
                delegate: RowLayout {
                    id: entry
                    required property int index
                    required property string modelData
                    property var info: null
                    property bool failed: false
                    readonly property bool shiny: page.isShiny(modelData)

                    Component.onCompleted: Api.fetchPokemon(modelData, function (err, data) {
                        entry.info = data;
                        entry.failed = !!err;
                    })

                    QQC2.RadioButton {
                        QQC2.ButtonGroup.group: activeGroup
                        checked: entry.index === page.cfg_activeIndex
                        onToggled: if (checked) page.cfg_activeIndex = entry.index
                        QQC2.ToolTip.text: i18n("Usar este Pokémon")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    Item {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.large
                        Layout.preferredHeight: Kirigami.Units.iconSizes.large
                        PokemonSprite {
                            anchors.fill: parent
                            source: Api.spriteUrl(entry.info, page.cfg_spriteStyle, entry.shiny)
                            pixelated: Api.isPixelStyle(page.cfg_spriteStyle)
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: entry.failed
                            source: "dialog-warning"
                        }
                    }

                    QQC2.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: entry.info
                            ? "#" + entry.info.id + " " + Api.displayName(entry.info.name)
                            : Api.displayName(entry.modelData)
                        font.bold: entry.index === page.cfg_activeIndex
                    }

                    QQC2.ToolButton {
                        text: "✨"
                        checkable: true
                        checked: entry.shiny
                        opacity: checked ? 1 : 0.35
                        onToggled: page.setShiny(entry.modelData, checked)
                        QQC2.ToolTip.text: checked ? i18n("Shiny (clique para voltar ao normal)") : i18n("Deixar shiny")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    QQC2.ToolButton {
                        icon.name: "arrow-up"
                        enabled: entry.index > 0
                        onClicked: page.move(entry.index, -1)
                    }
                    QQC2.ToolButton {
                        icon.name: "arrow-down"
                        enabled: entry.index < page.cfg_pokemonList.length - 1
                        onClicked: page.move(entry.index, 1)
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove"
                        onClicked: page.removeAt(entry.index)
                        QQC2.ToolTip.text: i18n("Remover")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: styleCombo
            Kirigami.FormData.label: i18n("Estilo do sprite:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Animado PMD (anda, dorme, pula)"), value: "pmd" },
                { text: i18n("Animado (Showdown)"), value: "animated" },
                { text: i18n("Pixel clássico"), value: "default" },
                { text: i18n("Arte oficial"), value: "artwork" },
                { text: i18n("Pokémon HOME (3D)"), value: "home" }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_spriteStyle))
            onActivated: page.cfg_spriteStyle = currentValue
        }

        QQC2.Label {
            visible: page.cfg_spriteStyle === "pmd"
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Sprites do <a href=\"https://sprites.pmdcollab.org\">PMD Sprite Collab</a> (CC BY-NC 4.0). Pokémon sem sprite PMD usam o GIF da PokeAPI.")
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Aparência:")
            text: i18n("Mostrar todos ao mesmo tempo")
            checked: page.cfg_showAll
            onToggled: page.cfg_showAll = checked
        }

        QQC2.CheckBox {
            text: i18n("Andar pela área do widget")
            checked: page.cfg_walk
            onToggled: page.cfg_walk = checked
        }

        QQC2.CheckBox {
            text: i18n("Pausar quando uma janela maximizada cobrir a área de trabalho")
            checked: page.cfg_pauseWhenCovered
            onToggled: page.cfg_pauseWhenCovered = checked
        }

        QQC2.CheckBox {
            text: i18n("Mostrar nome e tipos")
            checked: page.cfg_showName
            onToggled: page.cfg_showName = checked
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Trocar automaticamente a cada:")
            QQC2.SpinBox {
                from: 0
                to: 1440
                value: page.cfg_cycleInterval
                onValueModified: page.cfg_cycleInterval = value
            }
            QQC2.Label {
                text: page.cfg_cycleInterval === 0 ? i18n("minutos (desligado)") : i18n("minutos")
            }
        }
    }
}
