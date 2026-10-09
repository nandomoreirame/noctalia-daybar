import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.System
import qs.Services.Location
import "utils/store.js" as Store
import "utils/tasks.js" as Tasks
import "utils/inbox.js" as Inbox
import "utils/reminders.js" as Reminders
import "utils/khal.js" as Khal
import "utils/pomodoro.js" as Pomodoro
import "utils/writequeue.js" as WriteQueue
import "utils/focuslog.js" as FocusLog
import "utils/dates.js" as Dates

// Long-lived services: data store, IPC, agenda writes, reminders, pomodoro and
// the capture overlay. UI files only read state from here and call these functions.
Item {
  id: root

  property var pluginApi: null
  readonly property var settings: pluginApi?.pluginSettings ?? ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

  function setting(key) {
    const v = settings[key];
    return v === undefined ? defaults[key] : v;
  }

  // Writes one setting from inside the plugin UI (the Focus tab quick settings).
  function setSetting(key, value) {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings[key] = value;
    pluginApi.saveSettings();
  }

  // ---------------------------------------------------------------- store

  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/noctalia-daybar"
  readonly property string dataPath: dataDir + "/data.json"
  property var data: Store.createEmpty()
  property bool loaded: false
  property string requestedTab: ""

  function nowIso() {
    return new Date().toISOString();
  }

  function newId() {
    return Store.makeId(Date.now(), Math.random());
  }

  function commit(next) {
    root.data = next;
    saveTimer.restart();
  }

  function applyLoaded(text) {
    const r = Store.parse(text);
    root.data = r.data;
    root.loaded = true;
    if (r.corrupt) {
      Quickshell.execDetached(["mv", "-f", root.dataPath, root.dataPath + ".bak"]);
      ToastService.showWarning(pluginApi?.tr("store.corrupt-title"), pluginApi?.tr("store.corrupt-body"));
      saveTimer.restart();
    }
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.dataDir]
    running: true
    onExited: dataFile.path = root.dataPath
  }

  FileView {
    id: dataFile
    path: ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(dataFile.text())
    onLoadFailed: function (error) {
      root.applyLoaded("");
    }
  }

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (root.loaded)
        dataFile.setText(Store.serialize(root.data));
    }
  }

  // Tasks / events / inbox (called by the UI)
  function addTask(fields) { commit(Tasks.addTask(data, fields, newId(), nowIso())); }
  function toggleTask(id) { commit(Tasks.toggleTask(data, id, nowIso())); }
  function deleteTask(id) { commit(Tasks.deleteTask(data, id)); }
  function toggleEvent(uid, date) { commit(Tasks.toggleEventCheck(data, uid, date)); }
  function addLink(url) { commit(Inbox.addLink(data, url, newId(), nowIso())); }
  function archiveLink(id) { commit(Inbox.archiveLink(data, id)); }
  function addNote(text) { commit(Inbox.addNote(data, text, newId(), nowIso())); }
  function deleteNote(id) { commit(Inbox.deleteNote(data, id)); }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)]);
  }

  function openUrl(url) {
    if (Inbox.isHttpUrl(url))
      Quickshell.execDetached(["xdg-open", url]);
  }

  // ---------------------------------------------------------------- IPC

  IpcHandler {
    target: "plugin:daybar"

    function toggle(): void {
      if (root.pluginApi)
        root.pluginApi.withCurrentScreen(screen => root.pluginApi.togglePanel(screen));
    }

    function open(tab: string): void {
      if (!root.pluginApi)
        return;
      root.requestedTab = tab;
      root.pluginApi.withCurrentScreen(screen => root.pluginApi.openPanel(screen));
    }

    function capture(): void {
      root.openCapture();
    }
  }

  // ---------------------------------------------------------------- agenda

  readonly property bool calendarReady: CalendarService.available
  property var calendars: []
  property var writeQueue: WriteQueue.createQueue()
  property var syncState: WriteQueue.createSync()
  // token -> done(ok, error); kept apart from the queue so the queue stays plain data
  property var writeCallbacks: ({})
  readonly property bool writing: writeQueue.active !== null

  Process {
    id: calendarsProcess
    command: Khal.printCalendarsArgs()
    running: root.calendarReady
    stdout: StdioCollector {
      onStreamFinished: root.calendars = Khal.parseCalendars(text)
    }
  }

  function enqueueEvent(payload, done) {
    const r = WriteQueue.enqueue(writeQueue, payload);
    const callbacks = Object.assign({}, writeCallbacks);
    callbacks[r.queue.seq] = done;
    writeCallbacks = callbacks;
    writeQueue = r.queue;
    if (r.start)
      startWrite(r.start);
  }

  function startWrite(job) {
    khalNewProcess.token = job.token;
    khalNewProcess.command = Khal.newEventArgs(Object.assign({ calendar: setting("defaultCalendar") }, job.payload));
    khalWatchdog.restart();
    khalNewProcess.running = true;
  }

  // Settles the active write once, whichever signal arrives first (exit, a
  // failed start or the watchdog), then starts the next queued job.
  function finishWrite(token, ok, error) {
    const r = WriteQueue.settle(writeQueue, token);
    if (!r.settled)
      return;
    khalWatchdog.stop();
    writeQueue = r.queue;
    const done = writeCallbacks[token];
    const callbacks = Object.assign({}, writeCallbacks);
    delete callbacks[token];
    writeCallbacks = callbacks;
    if (ok)
      requestSync();
    if (done)
      done(ok, error);
    if (r.start)
      startWrite(r.start);
  }

  function requestSync() {
    const r = WriteQueue.requestSync(syncState);
    syncState = r.state;
    if (r.start)
      syncProcess.running = true;
  }

  Process {
    id: khalNewProcess
    property int token: 0
    stderr: StdioCollector {
      id: khalStderr
    }
    onExited: function (exitCode) {
      if (exitCode !== 0)
        Logger.w("Daybar", "khal new failed: " + khalStderr.text);
      root.finishWrite(khalNewProcess.token, exitCode === 0, "khal-failed");
    }
    // A binary that cannot start (khal missing) never emits exited; running just
    // drops back to false. Deferred so a normal exit settles first.
    onRunningChanged: {
      if (running)
        return;
      const token = khalNewProcess.token;
      Qt.callLater(() => root.finishWrite(token, false, "khal-failed"));
    }
  }

  Timer {
    id: khalWatchdog
    interval: 30000
    onTriggered: {
      Logger.w("Daybar", "khal new timed out");
      khalNewProcess.running = false;
      root.finishWrite(khalNewProcess.token, false, "khal-failed");
    }
  }

  Process {
    id: syncProcess
    command: Khal.syncArgs()
    onExited: function (exitCode) {
      if (exitCode !== 0)
        ToastService.showWarning(root.pluginApi?.tr("agenda.sync-failed-title"), root.pluginApi?.tr("agenda.sync-failed-body"));
      CalendarService.loadEvents();
    }
    // Rerun once when an event was written mid-sync; also covers a vdirsyncer
    // that fails to start, which never emits exited.
    onRunningChanged: {
      if (running)
        return;
      Qt.callLater(() => {
        const r = WriteQueue.syncFinished(root.syncState);
        root.syncState = r.state;
        if (r.start)
          syncProcess.running = true;
      });
    }
  }

  // ---------------------------------------------------------------- capture

  // result: a successful registry.resolve() result; done(ok, errorCode)
  function executeCapture(result, done) {
    const p = result.payload;
    if (result.action === "addTask") {
      addTask({ title: p.title, date: p.date, time: p.time });
      done(true, "");
    } else if (result.action === "addNote") {
      addNote(p.text);
      done(true, "");
    } else if (result.action === "addLink") {
      addLink(p.url);
      done(true, "");
    } else if (result.action === "createEvent") {
      if (!calendarReady)
        return done(false, "calendar-not-configured");
      enqueueEvent(p, done);
    } else if (result.action === "createReminder") {
      const remember = function () {
        commit(Reminders.addReminder(data, { title: p.title, date: p.date, time: p.start }, newId()));
      };
      if (!calendarReady) {
        remember();
        return done(true, "");
      }
      enqueueEvent(p, function (ok, error) {
        if (ok)
          remember();
        done(ok, error);
      });
    }
  }

  CaptureWindow {
    id: captureWindow
    pluginApi: root.pluginApi
    mainInstance: root
  }

  Process {
    id: clipboardProcess
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      onStreamFinished: {
        const url = Inbox.prefillFromClipboard(text, root.data);
        if (url)
          captureWindow.prefill(url);
      }
    }
  }

  function openCapture() {
    if (!pluginApi)
      return;
    pluginApi.withCurrentScreen(screen => {
      captureWindow.openOn(screen);
      clipboardProcess.running = true;
    });
  }

  // ---------------------------------------------------------------- reminders

  property string todayIso: Dates.isoDate(new Date())

  Timer {
    interval: 30000
    repeat: true
    running: root.loaded
    triggeredOnStart: true
    onTriggered: {
      const today = Dates.isoDate(new Date());
      if (today !== root.todayIso)
        root.todayIso = today;
      const due = Reminders.dueReminders(root.data, new Date());
      for (const r of due.fire)
        ToastService.showNotice(root.pluginApi?.tr("reminder.title"), r.title, "bell", 10000);
      const ids = due.fire.concat(due.expire).map(r => r.id);
      if (ids.length > 0)
        root.commit(Reminders.markFired(root.data, ids));
    }
  }

  // ---------------------------------------------------------------- pomodoro
  // Fork of the MIT "pomodoro" Noctalia plugin (see THIRD_PARTY.md).

  readonly property string alarmSoundFile: Qt.resolvedUrl("alarm.mp3").toString().replace("file://", "")
  readonly property var pomodoroConfig: Pomodoro.configFrom({
      workDuration: setting("workDuration"),
      shortBreakDuration: setting("shortBreakDuration"),
      longBreakDuration: setting("longBreakDuration"),
      sessionsBeforeLongBreak: setting("sessionsBeforeLongBreak"),
      dailyPomodoroGoal: setting("dailyPomodoroGoal"),
      autoStartBreaks: setting("autoStartBreaks"),
      autoStartWork: setting("autoStartWork")
    })
  readonly property int todaySessions: FocusLog.sessionsOn(data, todayIso)

  // A new duration applies at once to a phase that has not started yet.
  onPomodoroConfigChanged: pomodoroRemaining = Pomodoro.idleRemaining(pomodoroStarted, pomodoroRemaining, pomodoroMode, pomodoroConfig)

  property bool pomodoroRunning: false
  // True from Start until the phase ends, is reset, skipped or switched.
  property bool pomodoroStarted: false
  property int pomodoroMode: Pomodoro.WORK
  property int pomodoroCompleted: 0
  property int pomodoroRemaining: 0
  property bool pomodoroSoundPlaying: false
  property string linkedTaskId: ""

  readonly property bool focusShouldBeOn: pomodoroRunning && pomodoroMode === Pomodoro.WORK
  onFocusShouldBeOnChanged: {
    const cmd = String(setting("focusModeCommand") || "").trim();
    if (cmd)
      Quickshell.execDetached([cmd, focusShouldBeOn ? "on" : "off"]);
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.pomodoroRunning
    onTriggered: {
      root.pomodoroRemaining -= 1;
      if (root.pomodoroRemaining <= 0)
        root.pomodoroFinished();
    }
  }

  Timer {
    id: alarmLimitTimer
    interval: 5000
    onTriggered: root.pomodoroStopAlarm()
  }

  function pomodoroStart() {
    pomodoroStopAlarm();
    if (pomodoroRemaining <= 0)
      pomodoroRemaining = Pomodoro.durationFor(pomodoroMode, pomodoroConfig);
    pomodoroStarted = true;
    pomodoroRunning = true;
  }

  function pomodoroPause() {
    pomodoroRunning = false;
    pomodoroStopAlarm();
  }

  function pomodoroReset() {
    pomodoroRunning = false;
    pomodoroStarted = false;
    pomodoroRemaining = Pomodoro.durationFor(pomodoroMode, pomodoroConfig);
    pomodoroStopAlarm();
  }

  function pomodoroSkip() {
    pomodoroRunning = false;
    pomodoroStarted = false;
    pomodoroStopAlarm();
    const next = Pomodoro.nextPhase({ mode: pomodoroMode, completed: pomodoroCompleted }, pomodoroConfig);
    pomodoroMode = next.mode;
    pomodoroCompleted = next.completed;
    pomodoroRemaining = Pomodoro.durationFor(next.mode, pomodoroConfig);
  }

  function pomodoroSetMode(mode) {
    pomodoroRunning = false;
    pomodoroStarted = false;
    pomodoroStopAlarm();
    pomodoroMode = mode;
    pomodoroRemaining = Pomodoro.durationFor(mode, pomodoroConfig);
  }

  function pomodoroStopAlarm() {
    if (pomodoroSoundPlaying) {
      SoundService.stopSound(alarmSoundFile);
      pomodoroSoundPlaying = false;
      alarmLimitTimer.stop();
    }
  }

  function pomodoroFinished() {
    pomodoroRunning = false;
    pomodoroStarted = false;
    const outcome = Pomodoro.finish({ mode: pomodoroMode, completed: pomodoroCompleted }, pomodoroConfig);
    let goalReached = false;
    if (outcome.workCompleted) {
      let next = FocusLog.addSession(data, Dates.isoDate(new Date()));
      if (linkedTaskId)
        next = Tasks.addPomodoro(next, linkedTaskId);
      commit(next);
      goalReached = FocusLog.goalJustReached(FocusLog.sessionsOn(next, Dates.isoDate(new Date())), pomodoroConfig.dailyGoal);
    }
    if (setting("playSound") !== false) {
      SoundService.playSound(alarmSoundFile, { repeat: true, volume: 0.3 });
      pomodoroSoundPlaying = true;
      alarmLimitTimer.start();
    }
    ToastService.showNotice(pluginApi?.tr("focus.toast-title"), pluginApi?.tr(goalReached ? "focus.toast-goal-reached" : (outcome.workCompleted ? "focus.toast-work-done" : "focus.toast-break-done")), "clock");
    pomodoroMode = outcome.next.mode;
    pomodoroCompleted = outcome.next.completed;
    pomodoroRemaining = outcome.remaining;
    if (outcome.autoStart)
      Qt.callLater(() => { root.pomodoroRunning = true; });
  }

  Component.onCompleted: pomodoroRemaining = Pomodoro.idleRemaining(pomodoroStarted, pomodoroRemaining, pomodoroMode, pomodoroConfig)
}
