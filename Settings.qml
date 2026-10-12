import QtQuick 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import "utils/clock.js" as Clock

// Plugin settings. Noctalia calls saveSettings() when the dialog is confirmed.
ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance ?? null

  property int workDuration: 25
  property int shortBreakDuration: 5
  property int longBreakDuration: 15
  property int sessionsBeforeLongBreak: 4
  property int dailyPomodoroGoal: 8
  property bool autoStartBreaks: false
  property bool autoStartWork: false
  property bool playSound: true
  property string focusModeCommand: ""
  property string defaultCalendar: ""
  property string initialTab: "last"
  property bool fetchPreviews: true
  property string clockCorner: "top-right"
  property string clockSize: "medium"

  spacing: Style.marginM

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function value(key) {
    const s = pluginApi?.pluginSettings ?? {};
    const d = pluginApi?.manifest?.metadata?.defaultSettings ?? {};
    return s[key] === undefined ? d[key] : s[key];
  }

  function loadSettings() {
    workDuration = value("workDuration");
    shortBreakDuration = value("shortBreakDuration");
    longBreakDuration = value("longBreakDuration");
    sessionsBeforeLongBreak = value("sessionsBeforeLongBreak");
    dailyPomodoroGoal = value("dailyPomodoroGoal");
    autoStartBreaks = value("autoStartBreaks");
    autoStartWork = value("autoStartWork");
    playSound = value("playSound");
    focusModeCommand = value("focusModeCommand");
    defaultCalendar = value("defaultCalendar");
    initialTab = value("initialTab");
    fetchPreviews = value("fetchPreviews");
    clockCorner = value("clockCorner");
    clockSize = value("clockSize");
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    const s = pluginApi.pluginSettings;
    s.workDuration = workDuration;
    s.shortBreakDuration = shortBreakDuration;
    s.longBreakDuration = longBreakDuration;
    s.sessionsBeforeLongBreak = sessionsBeforeLongBreak;
    s.dailyPomodoroGoal = dailyPomodoroGoal;
    s.autoStartBreaks = autoStartBreaks;
    s.autoStartWork = autoStartWork;
    s.playSound = playSound;
    s.focusModeCommand = focusModeCommand.trim();
    s.defaultCalendar = defaultCalendar;
    s.initialTab = initialTab;
    s.fetchPreviews = fetchPreviews;
    s.clockCorner = clockCorner;
    s.clockSize = clockSize;
    pluginApi.saveSettings();
  }

  onPluginApiChanged: if (pluginApi) loadSettings()
  Component.onCompleted: if (pluginApi) loadSettings()

  NHeader {
    label: root.tr("settings.focus")
  }

  NSpinBox {
    label: root.tr("settings.work-duration")
    from: 1
    to: 180
    value: root.workDuration
    suffix: " min"
    onValueChanged: root.workDuration = value
  }

  NSpinBox {
    label: root.tr("settings.short-break")
    from: 1
    to: 60
    value: root.shortBreakDuration
    suffix: " min"
    onValueChanged: root.shortBreakDuration = value
  }

  NSpinBox {
    label: root.tr("settings.long-break")
    from: 1
    to: 120
    value: root.longBreakDuration
    suffix: " min"
    onValueChanged: root.longBreakDuration = value
  }

  NSpinBox {
    label: root.tr("settings.sessions")
    from: 1
    to: 12
    value: root.sessionsBeforeLongBreak
    onValueChanged: root.sessionsBeforeLongBreak = value
  }

  NSpinBox {
    label: root.tr("settings.daily-goal")
    description: root.tr("settings.daily-goal-help")
    from: 0
    to: 24
    value: root.dailyPomodoroGoal
    onValueChanged: root.dailyPomodoroGoal = value
  }

  NToggle {
    label: root.tr("settings.auto-start-breaks")
    checked: root.autoStartBreaks
    onToggled: checked => root.autoStartBreaks = checked
  }

  NToggle {
    label: root.tr("settings.auto-start-work")
    checked: root.autoStartWork
    onToggled: checked => root.autoStartWork = checked
  }

  NToggle {
    label: root.tr("settings.play-sound")
    checked: root.playSound
    onToggled: checked => root.playSound = checked
  }

  NComboBox {
    label: root.tr("settings.clock-corner")
    model: Clock.CORNERS.map(k => ({ key: k, name: root.tr("settings.clock-corners." + k) }))
    currentKey: root.clockCorner
    onSelected: key => root.clockCorner = key
  }

  NComboBox {
    label: root.tr("settings.clock-size")
    model: Object.keys(Clock.RING_SIZES).map(k => ({ key: k, name: root.tr("settings.clock-sizes." + k) }))
    currentKey: root.clockSize
    onSelected: key => root.clockSize = key
  }

  NTextInput {
    Layout.fillWidth: true
    label: root.tr("settings.focus-command")
    description: root.tr("settings.focus-command-help")
    text: root.focusModeCommand
    onTextChanged: root.focusModeCommand = text
  }

  NHeader {
    label: root.tr("settings.general")
  }

  NToggle {
    label: root.tr("settings.fetch-previews")
    description: root.tr("settings.fetch-previews-help")
    checked: root.fetchPreviews
    onToggled: checked => root.fetchPreviews = checked
  }

  NComboBox {
    label: root.tr("settings.default-calendar")
    description: root.mainInstance?.calendarReady ? "" : root.tr("calendar.not-configured")
    model: (root.mainInstance?.calendars ?? []).map(c => ({ key: c, name: c }))
    currentKey: root.defaultCalendar
    placeholder: root.tr("settings.default-calendar-none")
    onSelected: key => root.defaultCalendar = key
  }

  NComboBox {
    label: root.tr("settings.initial-tab")
    model: [{ key: "last", name: root.tr("settings.initial-tab-last") }].concat(["calendar", "today", "focus", "bookmarks", "notes"].map(k => ({ key: k, name: root.tr("tabs." + k) })))
    currentKey: root.initialTab
    onSelected: key => root.initialTab = key
  }
}
