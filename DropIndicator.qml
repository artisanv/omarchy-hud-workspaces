import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Big workspace-number confirmation for a window dropped on the bar.
//
// Hyprland gives the bar no way to notice a drag in progress (it withholds
// pointer focus from layer surfaces until the button comes back up), so this
// only ever appears after the drop has already happened. It is deliberately
// brief -- a confirmation, not a notification.
PanelWindow {
  id: root

  property int workspace: 0

  readonly property int holdMs: 400

  color: "transparent"
  exclusiveZone: -1
  aboveWindows: true

  // Empty input region: the surface covers the whole screen, so without this
  // it swallows every click that lands on it. Nothing here needs clicking.
  mask: Region {}

  WlrLayershell.namespace: "omarchy-workspace-drop"
  WlrLayershell.layer: WlrLayer.Overlay

  anchors { top: true; bottom: true; left: true; right: true }

  // Belt and braces with `mask`: only map the surface while the card is
  // actually up. A layer surface that exists but has no input region should
  // be inert anyway, but leaving nothing mapped is unambiguous.
  visible: false

  function showFor(id) {
    root.workspace = id
    root.visible = true
    anim.restart()
  }

  // In: fade and settle from just under full size (180 ms, ease-out).
  // Hold: the time to read it (not motion, so it stays with animations off).
  // Out: a shorter fade (120 ms).
  SequentialAnimation {
    id: anim

    ParallelAnimation {
      NumberAnimation {
        target: card
        property: "opacity"
        from: 0
        to: 1
        duration: Style.duration(180)
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: card
        property: "scale"
        from: 0.96
        to: 1
        duration: Style.duration(180)
        easing.type: Easing.Bezier
        easing.bezierCurve: Style.easeOut
      }
    }
    PauseAnimation { duration: root.holdMs }
    NumberAnimation {
      target: card
      property: "opacity"
      to: 0
      duration: Style.duration(120)
      easing.type: Easing.OutCubic
    }

    onStopped: {
      root.workspace = 0
      root.visible = false
    }
  }

  Item {
    anchors.fill: parent

    Item {
      anchors.centerIn: parent
      width: card.width
      height: card.height

      Rectangle {
        id: card

        anchors.centerIn: parent
        width: box.implicitWidth + Style.space(56)
        height: box.implicitHeight + Style.space(44)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(20)
        color: Util.alpha(Color.background, 0.82)
        border.width: Style.space(1)
        border.color: Util.alpha(Color.accent, 0.35)

        // Start hidden; the animation is what brings it up.
        opacity: 0
        scale: 0.96

        Column {
          id: box
          anchors.centerIn: parent
          spacing: 0

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.workspace === 10 ? "0" : String(root.workspace)
            color: Color.accent
            font.family: Style.font.family
            font.weight: Font.Bold
            font.pixelSize: Math.round(Style.space(150))
          }

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "workspace"
            color: Util.alpha(Color.foreground, 0.55)
            font.family: Style.font.family
            font.weight: Font.Medium
            font.pixelSize: Math.round(Style.space(15))
            font.letterSpacing: Style.space(2)
          }
        }
      }
    }
  }
}