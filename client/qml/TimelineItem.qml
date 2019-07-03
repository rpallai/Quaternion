import QtQuick 2.6
import QtQuick.Controls 1.4
import QtQuick.Controls 2.0 as QQC2
//import QtGraphicalEffects 1.0 // For fancy highlighting
import QMatrixClient 1.0

Item {
    // Supplementary components

    SystemPalette { id: defaultPalette; colorGroup: SystemPalette.Active }
    SystemPalette { id: disabledPalette; colorGroup: SystemPalette.Disabled }
    Settings {
        id: settings
        readonly property bool condense_chat: value("UI/condense_chat", false)
        readonly property bool autoload_images: value("UI/autoload_images", true)
        readonly property string highlight_mode: value("UI/highlight_mode", "background")
        readonly property string highlight_color: value("UI/highlight_color", "orange")
        readonly property string outgoing_color: value("UI/outgoing_color", "#204A87")
        readonly property string render_type: value("UI/Fonts/render_type", "NativeRendering")
        readonly property int animations_duration_ms: value("UI/animations_duration_ms", 400)
        readonly property int fast_animations_duration_ms: animations_duration_ms / 2
        readonly property string timeline_style: value("UI/timeline_style", "")
        readonly property bool show_author_avatars:
            value("UI/show_author_avatars", timeline_style != "xchat")
    }

    // Property interface

    /** Determines whether the view is moving at the moment */
    property var view
    property bool moving: view.moving

    // TimelineItem definition

    visible: marks !== EventStatus.Hidden
    enabled: visible
    height: childrenRect.height * visible

    readonly property bool sectionVisible: section !== aboveSection
    readonly property bool authorSectionVisible:
                            sectionVisible || author !== aboveAuthor
    readonly property bool redacted: marks === EventStatus.Redacted
    readonly property bool pending: [
                                        EventStatus.Submitted,
                                        EventStatus.Departed,
                                        EventStatus.ReachedServer,
                                        EventStatus.SendingFailed
                                    ].indexOf(marks) != -1
    readonly property bool failed: marks === EventStatus.SendingFailed
    readonly property bool eventWithTextPart: ["message", "emote", "image", "file"].indexOf(eventType) >= 0
    /*readonly*/ property string textColor:
        marks === EventStatus.Submitted || failed ? defaultPalette.mid :
        marks === EventStatus.Departed ? disabledPalette.text :
        redacted ? disabledPalette.text :
        (eventWithTextPart && author === room.localUser) ?
            Qt.tint(defaultPalette.text, settings.outgoing_color) :
        highlight && settings.highlight_mode == "text" ? settings.highlight_color :
        (["state", "notice", "other"].indexOf(eventType) >= 0) ?
                disabledPalette.text : defaultPalette.text
    readonly property string authorName: room && room.roomMembername(author.id)
    // FIXME: boilerplate with models/userlistmodel.cpp:115
    readonly property string authorColor: Qt.hsla(userHue,
                                                  (1-defaultPalette.window.hslSaturation),
                                                  /* contrast but not too heavy: */
                                                  (-0.7*defaultPalette.window.hslLightness + 0.9),
                                                  defaultPalette.buttonText.a)

    readonly property bool xchatStyle: settings.timeline_style === "xchat"
    readonly property bool actionEvent: eventType == "state" || eventType == "emote"

    // A message is considered shown if its bottom is within the
    // viewing area of the timeline.
    readonly property bool shown:
        y + message.height - 1 > view.contentY &&
        y + message.height - 1 < view.contentY + view.height

    onShownChanged: {
        if (!pending)
            controller.onMessageShownChanged(eventId, shown)
    }

    Component.onCompleted: {
        if (shown)
            shownChanged(true);
    }

    Behavior on textColor { ColorAnimation {
        duration: settings.animations_duration_ms
    }}

    property bool showingDetails

    Connections {
        target: controller
        onShowDetails: {
            if (currentIndex === index) {
                showingDetails = !showingDetails
                detailsAnimation.start()
            }
        }
    }

    SequentialAnimation {
        id: detailsAnimation
        PropertyAction {
            target: detailsAreaLoader; property: "visible"
            value: true
        }
        NumberAnimation {
            target: detailsAreaLoader; property: "opacity"
            to: showingDetails
            duration: settings.fast_animations_duration_ms
            easing.type: Easing.OutQuad
        }
        PropertyAction {
            target: detailsAreaLoader; property: "visible"
            value: showingDetails
        }
    }

    Column {
        id: fullMessage
        width: parent.width

        Rectangle {
            width: parent.width
            height: sectionLabel.height + 2
            visible: sectionVisible
            color: defaultPalette.window
            Label {
                id: sectionLabel
                font.bold: true
                renderType: settings.render_type
                text: section
            }
            TimelineMouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }
        Loader {
            id: detailsAreaLoader
//            asynchronous: true // https://bugreports.qt.io/browse/QTBUG-50992
            active: visible
            visible: false // Controlled by showDetailsButton
            opacity: 0
            width: parent.width

            sourceComponent: detailsArea

            TimelineMouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }

        Item {
            id: message
            width: parent.width
            height: messageContent.height

            TimelineMouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Item {
                id: messageContent
                width: parent.width
                height: childrenRect.height

                // There are several layout styles (av - author avatar,
                // al - author label, ts - timestamp, c - content
                // default (when "timeline_style" is not "xchat"):
                //   av al
                //   ts c
                // state-emote (default for state and emote events):
                //   av (al+c in a single control
                //   ts  spanning both rows)
                // xchat (when "timeline_style" is "xchat"):
                //   ts av al c
                // xchat state-emote
                //   ts av *(asterisk) al c

                Image {
                    id: authorAvatar
                    visible: settings.show_author_avatars && source &&
                             (authorSectionVisible || xchatStyle)
                    anchors.left: xchatStyle ? timelabel.right : parent.left
                    anchors.leftMargin: xchatStyle * 3
                    width: if (!xchatStyle) { timelabel.width }
                           else if (!visible) { 0 }
                    height: xchatStyle ? authorLabel.height :
                            visible ? authorLabel.height * 2 - timelabel.height : 0
                    fillMode: Image.PreserveAspectFit

                    source: author.avatarMediaId ?
                                "image://mtx/" + author.avatarMediaId : ""
                }
                Label {
                    id: authorLabel
                    visible: xchatStyle || (!actionEvent && authorSectionVisible)
                    anchors.left: authorAvatar.right
                    anchors.leftMargin: 2
                    anchors.top: authorAvatar.top
                    width: if (xchatStyle) { 120 - authorAvatar.width }
                    horizontalAlignment:
                        actionEvent ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight

                    color: authorColor
                    textFormat: Label.PlainText
                    font.bold: !xchatStyle
                    renderType: settings.render_type

                    text: (actionEvent ? "* " : "") + authorName
                }
                TimelineMouseArea {
                    anchors.left: authorAvatar.left
                    anchors.right: authorLabel.right
                    anchors.top: authorLabel.top
                    anchors.bottom:  authorLabel.bottom
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton|Qt.MiddleButton
                    hoverEnabled: true
                    onEntered: controller.showStatusMessage(author.id)
                    onExited: controller.showStatusMessage("")
                    onClicked: {
                        if (mouse.button === Qt.LeftButton)
                        {
                            controller.insertMention(author)
                            controller.focusInput()
                        } else
                            controller.resourceRequested(author.id)
                    }
                }

                Label {
                    id: timelabel
                    anchors.top: xchatStyle ? authorAvatar.top : authorAvatar.bottom
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    anchors.left: parent.left

                    color: disabledPalette.text
                    textFormat: Text.RichText
                    renderType: settings.render_type
                    font.italic: pending

                    text: "<font size=-1>&lt;" +
                          time.toLocaleTimeString(Qt.locale(), "hh:mm")
                          + "&gt;</font>"
                }

                Item {
                    id: highlighter
                    anchors.fill: textField
                    visible: highlight && settings.highlight_mode != "text"
                    // Uncomment for fancy highlighting
//                    RectangularGlow {
//                        anchors.fill: parent
//                        glowRadius: 5
//                        cornerRadius: 2
//                        color: settings.highlight_color
//                        cached: true
//                    }
//                    Rectangle {
//                        anchors.fill: parent
//                        border.color: settings.highlight_color
//                        border.width: 1
//                    }
                    Rectangle {
                        anchors.fill: parent
                        opacity: 0.2
                        color: settings.highlight_color
                        radius: 2
                    }
                }
                Item {
                    id: textField
                    anchors.top: !xchatStyle && authorLabel.visible
                                 ? authorLabel.bottom : authorAvatar.top
                    anchors.left: xchatStyle ? authorLabel.right : timelabel.right
                    anchors.leftMargin: 1
                    anchors.right: resendButton.left
                    anchors.rightMargin: 1
                    height: textFieldImpl.height
                    clip: true

                    TextEdit {
                        id: textFieldImpl
                        anchors.top: textField.top
                        width: parent.width
                        leftPadding: 2
                        rightPadding: 2
                        x: -textScrollBar.position * contentWidth

                        // Doesn't work for attributes
                        function toHtmlEscaped(txt) {
                            // Make sure to replace & first
                            return txt.replace(/&/g, '&amp;')
                                      .replace(/</g, '&lt;').replace(/>/g, '&gt;')
                        }

                        selectByMouse: true
                        readOnly: true
                        textFormat: TextEdit.RichText
                        // FIXME: The text is clumsy and slows down creation
                        text: (actionEvent && !xchatStyle ?
                               ("<a href='" + author.id + "' style='text-decoration:none;color:\"" +
                                        authorColor + "\"'><b>" +
                                        toHtmlEscaped(authorName) + "</b></a> ") : ""
                              ) + display +
                              (annotation ? "<br><em>" + annotation + "</em>" : "")
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.Wrap
                        color: textColor
                        renderType: settings.render_type

                        // TODO: In the code below, links should be resolved
                        // with Qt.resolvedLink, once we figure out what
                        // to do with relative URLs (note: www.google.com
                        // is a relative URL, https://www.google.com is not).
                        // Instead of Qt.resolvedUrl (and, most likely,
                        // QQmlAbstractUrlInterceptor to convert URLs)
                        // we might just prefer to do the whole resolving
                        // in C++.
                        onHoveredLinkChanged:
                            controller.showStatusMessage(hoveredLink)

                        onLinkActivated: {
                            if (link.startsWith("@")
                                || link.startsWith("https://matrix.to/#/@"))
                            {
                                controller.resourceRequested(link, "mention")
                                controller.focusInput()
                            }
                            else if (link.startsWith("https://matrix.to/"))
                                controller.resourceRequested(link)
                            else
                                Qt.openUrlExternally(link)
                        }

                        TimelineTextEditSelector {}
                    }

                    TimelineMouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.MiddleButton

                        onClicked: {
                            if (textFieldImpl.hoveredLink)
                                controller.resourceRequested(
                                    textFieldImpl.hoveredLink)
                        }
                    }

                    TimelineMouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: controller.showMenu(index,
                            textFieldImpl.hoveredLink, showingDetails)
                    }

                    TimelineMouseArea {
                        anchors.fill: parent
                        cursorShape: textFieldImpl.hoveredLink
                                     ? Qt.PointingHandCursor : Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton

                        onWheel: {
                            if (wheel.angleDelta.x != 0 &&
                                    textFieldImpl.width < textFieldImpl.contentWidth)
                            {
                                if (wheel.pixelDelta.x != 0)
                                    textScrollBar.position -=
                                                wheel.pixelDelta.x / width
                                else
                                    textScrollBar.position -=
                                                wheel.angleDelta.x / 6 / width
                                textScrollBar.position =
                                        Math.min(1, Math.max(0,
                                            textScrollBar.position))
                            } else
                                wheel.accepted = false
                        }
                    }
                    QQC2.ScrollBar {
                        id: textScrollBar
                        hoverEnabled: true
                        visible: textFieldImpl.contentWidth > textFieldImpl.width
                        active: visible
                        orientation: Qt.Horizontal
                        size: textFieldImpl.width / textFieldImpl.contentWidth
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                    }
                }

                Loader {
                    active: eventType == "image"

                    anchors.top: textField.bottom
                    anchors.left: textField.left
                    anchors.right: textField.right

                    sourceComponent: ImageContent {
                        property var info:
                            !progressInfo.isUpload && !progressInfo.active &&
                            content.info && content.info.thumbnail_info
                            ? content.info.thumbnail_info
                            : content.info
                        sourceSize: if (info) { Qt.size(info.w, info.h) }
                        source: downloaded || progressInfo.isUpload
                                ? progressInfo.localPath
                                : content.info && content.info.thumbnail_info && !autoload
                                  ? "image://mtx/" + content.thumbnailMediaId
                                  : ""
                        maxHeight: chatView.height - textField.height -
                                   authorLabel.height * !xchatStyle
                        autoload: settings.autoload_images
                    }
                }
                Loader {
                    active: eventType == "file"

                    anchors.top: textField.bottom
                    anchors.left: textField.left
                    anchors.right: textField.right
                    height: childrenRect.height

                    sourceComponent: FileContent { }
                }
                ToolButton {
                    id: resendButton
                    visible: failed
                    width: visible * implicitWidth
                    height: visible * implicitHeight
                    anchors.top: textField.top
                    anchors.right: discardButton.left
                    anchors.rightMargin: 2
                    text: qsTr("Resend")

                    onClicked: room.retryMessage(eventId)
                }
                ToolButton {
                    id: discardButton
                    visible: pending && marks !== EventStatus.ReachedServer
                             && marks !== EventStatus.Departed
                    width: visible * implicitWidth
                    height: visible * implicitHeight
                    anchors.top: textField.top
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    text: qsTr("Discard")

                    onClicked: room.discardMessage(eventId)
                }
                ToolButton {
                    id: goToPredecessorButton
                    visible: !pending && eventResolvedType == "m.room.create"
                    width: visible * implicitWidth
                    height: visible * implicitHeight
                    anchors.top: textField.top
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    text: qsTr("Go to\nolder room")

                    // TODO: Treat unjoined invite-only rooms specially
                    onClicked: controller.joinRequested(refId)
                }
                ToolButton {
                    id: goToSuccessorButton
                    visible: !pending && eventResolvedType == "m.room.tombstone"
                    width: visible * implicitWidth
                    height: visible * implicitHeight
                    anchors.top: textField.top
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    text: qsTr("Go to\nnew room")

                    // TODO: Treat unjoined invite-only rooms specially
                    onClicked: controller.joinRequested(refId)
                }
            }
        }
    }
    Rectangle {
        id: readMarkerLine

        width: readMarker && parent.width
        height: 3
        anchors.horizontalCenter: fullMessage.horizontalCenter
        anchors.bottom: fullMessage.bottom
        Behavior on width { NumberAnimation {
            duration: settings.animations_duration_ms
            easing.type: Easing.OutQuad
        }}

        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: defaultPalette.highlight }
        }
    }

    // Components loaded on demand

    Component {
        id: detailsArea

        Rectangle {
            height: childrenRect.height
            radius: 5

            color: defaultPalette.button
            border.color: defaultPalette.mid

            readonly property url evtLink:
                "https://matrix.to/#/" + room.id + "/" + eventId
            readonly property string sourceText: toolTip

            Item {
                id: detailsHeader
                width: parent.width
                height: childrenRect.height
                anchors.top: parent.top

                TextEdit {
                    text: "<" + time.toLocaleString(Qt.locale(), Locale.ShortFormat) + ">"
                    font.bold: true
                    renderType: settings.render_type
                    readOnly: true
                    selectByKeyboard: true; selectByMouse: true

                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    z: 1

                    TimelineTextEditSelector {}
                }
                TextEdit {
                    text: "<a href=\"" + evtLink + "\">"+ eventId
                          + "</a> (" + eventResolvedType + ")"
                    textFormat: Text.RichText
                    font.bold: true
                    renderType: settings.render_type
                    horizontalAlignment: Text.AlignHCenter
                    readOnly: true
                    selectByKeyboard: true; selectByMouse: true

                    width: parent.width

                    onLinkActivated: Qt.openUrlExternally(link)

                    TimelineTextEditSelector {}

                    TimelineMouseArea {
                        anchors.fill: parent
                        cursorShape: parent.hoveredLink ?
                                         Qt.PointingHandCursor :
                                         Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }
                }
                TextEdit {
                    id: permalink
                    text: evtLink
                    renderType: settings.render_type
                    width: 0; height: 0; visible: false
                }
            }

            TextArea {
                text: sourceText
                textFormat: Text.PlainText
                readOnly: true;
                font.family: "Monospace"
                // FIXME: make settings.render_type an integer (but store as string to stay human-friendly)
//                style: TextAreaStyle {
//                    renderType: settings.render_type
//                }
                selectByKeyboard: true; selectByMouse: true

                width: parent.width
                anchors.top: detailsHeader.bottom

                TimelineTextEditSelector {}
            }
        }
    }
}
