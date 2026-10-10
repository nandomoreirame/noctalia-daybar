import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.System
import qs.Services.Location
import "utils/store.js" as Store
import "utils/tasks.js" as Tasks
import "utils/url.js" as Url
import "utils/bookmarks.js" as Bookmarks
import "utils/notes.js" as Notes
import "utils/pagemeta.js" as PageMeta
import "utils/fetch.js" as Fetch
import "utils/fetchpool.js" as FetchPool
import "utils/reminders.js" as Reminders
import "utils/khal.js" as Khal
import "utils/pomodoro.js" as Pomodoro
import "utils/writequeue.js" as WriteQueue
import "utils/focuslog.js" as FocusLog
import "utils/dates.js" as Dates
import "utils/tabs.js" as Tabs
import "utils/eventdelete.js" as EventDelete
import "utils/today.js" as Today

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

  // Tasks, events, bookmarks and notes (called by the UI)
  function addTask(fields) { commit(Tasks.addTask(data, fields, newId(), nowIso())); }
  function toggleTask(id) { commit(Tasks.toggleTask(data, id, nowIso())); }
  function deleteTask(id) { commit(Tasks.deleteTask(data, id)); }
  function renameTask(id, title) {
    const next = Tasks.renameTask(data, id, title);
    if (next !== data)
      commit(next);
  }
  function setLastTab(key) {
    const next = Tabs.setLastTab(data, key);
    if (next !== data)
      commit(next);
  }
  function toggleEvent(uid, date) { commit(Tasks.toggleEventCheck(data, uid, date)); }
  // ---------------------------------------------------------------- bookmarks

  readonly property string thumbsDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/noctalia-daybar/thumbs"
  readonly property bool fetchPreviews: setting("fetchPreviews") !== false
  property var fetchPool: FetchPool.createPool(3)

  Process {
    command: ["mkdir", "-p", root.thumbsDir]
    running: true
  }

  // Turning previews off drops the queue; the dropped bookmarks leave "pending".
  onFetchPreviewsChanged: {
    if (fetchPreviews)
      return;
    const r = FetchPool.dropQueue(fetchPool);
    fetchPool = r.pool;
    let next = data;
    for (const job of r.dropped)
      next = Bookmarks.markOff(next, job.id, job.token);
    if (next !== data)
      commit(next);
  }

  // Returns "saved", "replaced" or "invalid".
  function addBookmark(url) {
    const r = Bookmarks.add(data, url, newId(), nowIso(), fetchPreviews);
    if (!r)
      return "invalid";
    commit(r.data);
    if (fetchPreviews)
      requestPreview(r.bookmark);
    return r.replaced ? "replaced" : "saved";
  }

  function refreshBookmark(id) {
    const r = Bookmarks.refresh(data, id, nowIso(), fetchPreviews);
    if (!r)
      return;
    commit(r.data);
    if (fetchPreviews)
      requestPreview(r.bookmark);
  }

  function renameBookmark(id, title) { commit(Bookmarks.rename(data, id, title)); }

  function deleteBookmark(id) {
    const path = Fetch.thumbPath(thumbsDir, id);
    commit(Bookmarks.remove(data, id));
    if (path)
      Quickshell.execDetached(Fetch.removeArgs(path));
  }

  function requestPreview(bookmark) {
    const r = FetchPool.request(fetchPool, { id: bookmark.id, token: bookmark.token, url: bookmark.url });
    fetchPool = r.pool;
    r.start.forEach(startPreview);
  }

  function finishPreview(id) {
    const r = FetchPool.finish(fetchPool, id);
    fetchPool = r.pool;
    r.start.forEach(startPreview);
  }

  Component {
    id: pageFetcher
    Process {
      property var job: null
      stdout: StdioCollector {
        id: pageOut
      }
      onExited: function (exitCode) {
        root.onPageFetched(job, exitCode, pageOut.text);
        destroy();
      }
    }
  }

  Component {
    id: imageFetcher
    Process {
      property var job: null
      property string path: ""
      onExited: function (exitCode) {
        // Keep the file only if the bookmark still exists with this token
        // (it may have been deleted or re-saved while downloading). A failed
        // or stale download also removes any previous thumb for this id and
        // clears the image path so the bookmark does not point at a deleted file.
        if (exitCode === 0 && Bookmarks.isCurrent(root.data, job.id, job.token))
          root.commit(Bookmarks.setImage(root.data, job.id, job.token, path));
        else {
          Quickshell.execDetached(Fetch.removeArgs(path));
          if (Bookmarks.isCurrent(root.data, job.id, job.token))
            root.commit(Bookmarks.setImage(root.data, job.id, job.token, ""));
        }
        root.finishPreview(job.id);
        destroy();
      }
    }
  }

  function startPreview(job) {
    // Deleted or re-saved while queued: skip, the newer job (if any) is queued.
    if (!Bookmarks.isCurrent(data, job.id, job.token)) {
      Qt.callLater(() => root.finishPreview(job.id));
      return;
    }
    const p = pageFetcher.createObject(root, { job: job, command: Fetch.pageArgs(job.url) });
    p.running = true;
  }

  function removeThumb(id) {
    const path = Fetch.thumbPath(thumbsDir, id);
    if (path)
      Quickshell.execDetached(Fetch.removeArgs(path));
  }

  function onPageFetched(job, exitCode, stdout) {
    // Relative og:image URLs resolve against the page reached after redirects.
    const page = Fetch.splitPageOutput(stdout, job.url);
    const meta = Fetch.isUsableExit(exitCode) ? PageMeta.parse(page.html, page.finalUrl) : null;
    if (!meta || (!meta.title && !meta.description && !meta.image)) {
      commit(Bookmarks.markFailed(data, job.id, job.token));
      if (Bookmarks.isCurrent(data, job.id, job.token))
        removeThumb(job.id);
      finishPreview(job.id);
      return;
    }
    commit(Bookmarks.applyPreview(data, job.id, job.token, meta));
    const path = Fetch.thumbPath(thumbsDir, job.id);
    if (!Bookmarks.isCurrent(data, job.id, job.token) || !path) {
      finishPreview(job.id);
      return;
    }
    // Only download og:image when the host is publicly routable (SSRF guard).
    // The bookmark URL itself may be a local service; the page-chosen image may not.
    if (!meta.image || !Url.isPublicHttpUrl(meta.image)) {
      commit(Bookmarks.setImage(data, job.id, job.token, ""));
      removeThumb(job.id);
      finishPreview(job.id);
      return;
    }
    const img = imageFetcher.createObject(root, { job: job, path: path, command: Fetch.imageArgs(meta.image, path) });
    img.running = true;
  }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)]);
  }

  function openUrl(url) {
    if (Url.isHttpUrl(url))
      Quickshell.execDetached(["xdg-open", url]);
  }

  // ---------------------------------------------------------------- notes

  function addNote(text) { commit(Notes.add(data, text, newId(), nowIso())); }
  function updateNote(id, text) { commit(Notes.update(data, id, text, nowIso())); }
  function deleteNote(id) {
    commit(Notes.remove(data, id));
    if (noteWindow.noteId === id)
      noteWindow.closeWindow(false);
  }

  // New notes are created on first non-blank save, so an untouched one leaves nothing behind.
  function openNote(id) { showNote(id); }
  function newNote() { showNote(""); }

  // The note window replaces the toolbar panel: close it so only the note stays.
  function showNote(id) {
    if (!pluginApi)
      return;
    if (pluginApi.panelOpenScreen)
      pluginApi.closePanel(pluginApi.panelOpenScreen);
    pluginApi.withCurrentScreen(screen => noteWindow.openOn(screen, id));
  }

  // Called by the note window: creates the note on first save when it is new.
  function saveNoteText(id, text) {
    if (id === "") {
      if (Notes.isBlank(text))
        return "";
      const newIdValue = newId();
      commit(Notes.add(data, text, newIdValue, nowIso()));
      return newIdValue;
    }
    updateNote(id, text);
    return id;
  }

  NoteWindow {
    id: noteWindow
    pluginApi: root.pluginApi
    mainInstance: root
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

    // Toggles, so the same shortcut opens and closes the overlay.
    function capture(): void {
      root.toggleCapture();
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

  readonly property string khalConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/khal/config"
  property var calendarRootsList: []
  property var calendarSectionList: []
  property var collections: []
  // Keys are EventDelete.eventKey(uid, calendar); cleared after the sync reload.
  property var hiddenEventUids: []
  // Set in the sync exit handler; cleared together with hiddenEventUids once
  // CalendarService.events has actually been replaced (onEventsChanged).
  property bool clearHiddenOnReload: false
  // CalendarService.events without the events deleted in this session (until reload).
  readonly property var visibleEvents: EventDelete.hideEvents(CalendarService.events, hiddenEventUids)

  Connections {
    target: CalendarService
    function onEventsChanged() {
      if (root.clearHiddenOnReload) {
        root.hiddenEventUids = [];
        root.clearHiddenOnReload = false;
      }
    }
  }

  function canDeleteEvent(calendarName) {
    return calendarReady && EventDelete.isWritableCalendar(collections, calendarName);
  }

  Process {
    id: khalConfigProcess
    command: EventDelete.readArgs(root.khalConfigPath)
    running: root.calendarReady
    stdout: StdioCollector {
      onStreamFinished: {
        const home = Quickshell.env("HOME");
        root.calendarRootsList = EventDelete.calendarRoots(text, home);
        root.calendarSectionList = EventDelete.calendarSections(text, home);
        if (root.calendarRootsList.length > 0) {
          collectionsProcess.command = EventDelete.collectionsArgs(root.calendarRootsList);
          collectionsProcess.running = true;
        }
      }
    }
  }

  Process {
    id: collectionsProcess
    stdout: StdioCollector {
      onStreamFinished: root.collections = EventDelete.parseCollections(text, root.calendarSectionList)
    }
  }

  Component {
    id: eventLookup
    Process {
      property var done: null
      property bool exitedDone: false
      property bool streamDone: false
      property string outText: ""
      stdout: StdioCollector {
        onStreamFinished: {
          outText = text;
          streamDone = true;
          maybeFinish();
        }
      }
      onExited: {
        exitedDone = true;
        maybeFinish();
      }
      function maybeFinish() {
        if (!exitedDone || !streamDone)
          return;
        done(outText);
        destroy();
      }
    }
  }

  function runOnce(command, done) {
    const p = eventLookup.createObject(root, { command: command, done: done });
    p.running = true;
  }

  // done({ ok, path, recurring } | { ok: false, error })
  function resolveEvent(uid, calendarName, done) {
    if (calendarRootsList.length === 0)
      return done({ ok: false, error: "not-found" });
    runOnce(EventDelete.findArgs(uid, calendarRootsList), function (out) {
      const pick = EventDelete.pickFile(EventDelete.parsePaths(out), root.collections, calendarName);
      if (!pick.ok) {
        if (pick.error === "not-found")
          CalendarService.loadEvents();
        return done(pick);
      }
      runOnce(EventDelete.readArgs(pick.path), function (ics) {
        done({ ok: true, path: pick.path, recurring: EventDelete.isRecurring(ics) });
      });
    });
  }

  Component {
    id: eventRemover
    Process {
      property string uid: ""
      property string calendar: ""
      onExited: function (exitCode) {
        root.onEventFileRemoved(uid, calendar, exitCode === 0);
        destroy();
      }
    }
  }

  function deleteEvent(uid, calendar, path) {
    if (!EventDelete.isDeletablePath(path, calendarRootsList)) {
      ToastService.showWarning(pluginApi?.tr("events.error.title"), pluginApi?.tr("events.error.failed"));
      return;
    }
    const p = eventRemover.createObject(root, { uid: uid, calendar: calendar, command: EventDelete.deleteArgs(path) });
    p.running = true;
  }

  function onEventFileRemoved(uid, calendar, ok) {
    if (!ok) {
      ToastService.showWarning(pluginApi?.tr("events.error.title"), pluginApi?.tr("events.error.failed"));
      return;
    }
    hiddenEventUids = hiddenEventUids.concat([EventDelete.eventKey(uid, calendar)]);
    // Checks are keyed by uid only (no calendar on the check record).
    commit(EventDelete.removeEventChecks(data, uid));
    requestSync();
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

  readonly property bool syncing: syncState.running

  // Toolbar reload: pull from Google, then reload the calendar service (done by
  // syncProcess on exit). Without khal there is nothing to sync, just reload.
  function refreshCalendar() {
    if (calendarReady)
      requestSync();
    else
      CalendarService.loadEvents();
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
      // Defer clearing optimistic hides until CalendarService.events is replaced;
      // clearing earlier lets the still-loaded deleted event flicker back.
      root.clearHiddenOnReload = true;
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
    } else if (result.action === "addBookmark") {
      const outcome = addBookmark(p.url);
      done(outcome !== "invalid", outcome === "invalid" ? "invalid-url" : "");
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
        const url = Bookmarks.prefillFromClipboard(text, root.data);
        if (url)
          captureWindow.prefill(url);
      }
    }
  }

  function toggleCapture() {
    if (captureWindow.visible)
      captureWindow.close();
    else
      openCapture();
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
  // done/total shown next to the Today and Calendar labels in the bar.
  readonly property var todayProgress: loaded && data?.tasks ? Today.todayProgress(visibleEvents, data, todayIso) : null
  readonly property var calendarProgress: loaded && data?.tasks ? Today.dayProgress(visibleEvents, data, todayIso) : null

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

  readonly property bool canFocusTask: Pomodoro.canFocusTask(pomodoroRunning, pomodoroMode)

  // Today's play button: link the task, switch to a focus phase (ending a running
  // break) and start, then show the Focus tab.
  function focusTask(id) {
    if (!canFocusTask)
      return;
    linkedTaskId = id;
    if (pomodoroMode !== Pomodoro.WORK)
      pomodoroSetMode(Pomodoro.WORK);
    pomodoroStart();
    requestedTab = "focus";
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
