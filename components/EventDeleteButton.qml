import QtQuick
import qs.Services.UI
import "ui"

// Trash for a synced event: locates its .ics when the bubble opens, then asks
// (recurring events say all occurrences go), then deletes through Main.
ConfirmButton {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string uid: ""
  property string calendar: ""
  property var target: null   // { path, recurring } once located

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  icon: "trash"
  tooltipText: tr("events.delete")
  ready: target !== null
  question: target === null ? tr("events.locating") : tr(target.recurring ? "events.confirm-delete-recurring" : "events.confirm-delete")
  okText: tr("confirm.ok")
  cancelText: tr("confirm.cancel")

  onOpened: {
    target = null;
    const asked = uid;
    mainInstance.resolveEvent(uid, calendar, function (r) {
      if (asked !== root.uid)
        return;
      if (!r.ok) {
        root.close();
        ToastService.showWarning(root.tr("events.error.title"), root.tr("events.error." + r.error));
        return;
      }
      root.target = r;
    });
  }

  onConfirmed: {
    if (target)
      mainInstance.deleteEvent(uid, target.path);
  }
}
