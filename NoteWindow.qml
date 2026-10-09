import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import "components/ui"
import "utils/notes.js" as Notes
import "utils/markdown.js" as Markdown
import "utils/format.js" as Format

// Large overlay for one note: Markdown preview by default, plain-text editor on
// demand. Saves 600 ms after the last keystroke, on Ctrl+S and on close.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string noteId: ""      // "" = new note not saved yet
  // True when this window created the note (autosave of a "New note"), so a note
  // emptied again before closing is discarded instead of saved blank.
  property bool createdHere: false
  property bool editing: false
  property string text: ""
  readonly property var note: mainInstance && noteId !== "" ? mainInstance.data.notes.find(n => n.id === noteId) || null : null
  readonly property string title: Notes.titleOf(text) || tr("notes.untitled")

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-note"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function openOn(targetScreen, id) {
    if (visible)
      closeWindow();
    createdHere = false;
    screen = targetScreen;
    noteId = id;
    const n = id !== "" ? mainInstance.data.notes.find(x => x.id === id) : null;
    text = n ? n.text : "";
    editing = id === "";
    visible = true;
    if (editing)
      Qt.callLater(focusEditor);
  }

  function focusEditor() {
    editor.text = root.text;
    editor.forceActiveFocus();
    editor.cursorPosition = editor.text.length;
  }

  function save() {
    saveTimer.stop();
    const wasNew = noteId === "";
    noteId = mainInstance.saveNoteText(noteId, text);
    if (wasNew && noteId !== "")
      createdHere = true;
  }

  // save=false when the note was just deleted.
  function closeWindow(saveFirst) {
    if (saveFirst !== false) {
      if (noteId !== "" && Notes.closeAction(createdHere, text) === "discard") {
        saveTimer.stop();
        mainInstance.deleteNote(noteId);
        return;
      }
      save();
    }
    createdHere = false;
    visible = false;
    editing = false;
    noteId = "";
    text = "";
  }

  function toggleEdit() {
    if (editing) {
      save();
      editing = false;
    } else {
      editing = true;
      Qt.callLater(focusEditor);
    }
  }

  function edited() {
    if (!note)
      return "";
    const r = Format.relativeTime(note.updatedAt, new Date());
    const when = r.unit === "date" ? r.date : tr("time." + r.unit).replace("{n}", r.n);
    return tr("notes.edited").replace("{time}", when);
  }

  Timer {
    id: saveTimer
    interval: 600
    onTriggered: root.save()
  }

  Shortcut {
    sequence: "Ctrl+E"
    enabled: root.visible
    onActivated: root.toggleEdit()
  }
  Shortcut {
    sequence: "Ctrl+S"
    enabled: root.visible
    onActivated: root.save()
  }
  // Disabled while the delete bubble is open: its own Esc must only cancel it,
  // and two Escape shortcuts in one window are ambiguous (neither fires).
  Shortcut {
    sequence: "Escape"
    enabled: root.visible && !noteTrash.asking
    onActivated: root.closeWindow()
  }

  // Dimmed backdrop; a click outside the card closes (saving).
  MouseArea {
    anchors.fill: parent
    onClicked: root.closeWindow()

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(Color.mShadow, 0.35)
    }
  }

  Rectangle {
    width: Math.min(1100 * Style.uiScaleRatio, parent.width * 0.9)
    height: Math.min(800 * Style.uiScaleRatio, parent.height * 0.9)
    anchors.centerIn: parent
    radius: Style.radiusL
    color: Color.mSurface
    border.color: Qt.alpha(Color.mOnSurface, 0.08)
    border.width: Style.borderS

    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Math.round(18 * Style.uiScaleRatio)
      spacing: Math.round(12 * Style.uiScaleRatio)

      RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(6 * Style.uiScaleRatio)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.title
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightSemiBold
            color: Color.mOnSurface
          }

          NText {
            visible: root.note !== null
            text: root.edited()
            pointSize: Style.fontSizeXS
            color: Qt.alpha(Color.mOnSurface, 0.42)
          }
        }

        PillButton {
          icon: root.editing ? "eye" : "pencil"
          tooltipText: root.editing ? root.tr("notes.preview") : root.tr("notes.edit")
          onClicked: root.toggleEdit()
        }
        PillButton {
          icon: "copy"
          tooltipText: root.tr("notes.copy")
          onClicked: root.mainInstance.copyText(root.text)
        }
        ConfirmButton {
          id: noteTrash
          visible: root.noteId !== ""
          icon: "trash"
          tooltipText: root.tr("notes.delete")
          question: root.tr("notes.confirm-delete")
          okText: root.tr("confirm.ok")
          cancelText: root.tr("confirm.cancel")
          onConfirmed: root.mainInstance.deleteNote(root.noteId)
        }
        PillButton {
          icon: "x"
          tooltipText: root.tr("notes.close")
          onClicked: root.closeWindow()
        }
      }

      NScrollView {
        id: previewScroll
        visible: !root.editing
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        horizontalPolicy: ScrollBar.AlwaysOff

        NText {
          width: previewScroll.availableWidth
          wrapMode: Text.Wrap
          markdownTextEnabled: true
          text: Markdown.prepare(root.text)
          pointSize: Style.fontSizeM
          color: Color.mOnSurface
          linkColor: Color.mPrimary
          onLinkActivated: link => {
            if (Markdown.isOpenableLink(link))
              Quickshell.execDetached(["xdg-open", link]);
          }

          TapHandler {
            onDoubleTapped: root.toggleEdit()
          }
        }
      }

      ScrollView {
        visible: root.editing
        Layout.fillWidth: true
        Layout.fillHeight: true

        TextArea {
          id: editor
          wrapMode: TextArea.Wrap
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * Style.uiScaleRatio
          color: Color.mOnSurface
          placeholderText: root.tr("notes.placeholder")
          placeholderTextColor: Qt.alpha(Color.mOnSurface, 0.42)
          selectionColor: Qt.alpha(Color.mPrimary, 0.4)
          background: Rectangle {
            radius: Math.round(12 * Style.uiScaleRatio)
            color: Qt.alpha(Color.mOnSurface, 0.05)
          }
          onTextChanged: {
            if (!root.editing || text === root.text)
              return;
            root.text = text;
            saveTimer.restart();
          }
        }
      }

      NText {
        text: root.tr("notes.keys")
        pointSize: Style.fontSizeXS
        color: Qt.alpha(Color.mOnSurface, 0.42)
      }
    }
  }
}
