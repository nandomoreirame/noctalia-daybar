.pragma library
.import "dates.js" as Dates

// Language-neutral pieces for the capture preview; QML translates `day` keys.
// describeWhen("2026-10-10", "15:00", "16:00", now) -> { day: "tomorrow", time: "15:00–16:00" }
// `day` is "today" | "tomorrow" | "dd/mm" | "" (no date).

function describeWhen(date, start, end, now) {
  let day = "";
  if (date) {
    const today = Dates.isoDate(now);
    const tomorrow = Dates.isoDate(Dates.addDays(now, 1));
    if (date === today) day = "today";
    else if (date === tomorrow) day = "tomorrow";
    else day = date.slice(8, 10) + "/" + date.slice(5, 7);
  }
  const time = start ? (end ? start + "–" + end : start) : "";
  return { day: day, time: time };
}

// "now" < 1 min (or in the future), then minutes, hours, days up to 6, else the date.
function relativeTime(iso, now) {
  const ms = now.getTime() - new Date(iso).getTime();
  const min = Math.floor(ms / 60000);
  if (min < 1) return { unit: "now", n: 0 };
  if (min < 60) return { unit: "minutes", n: min };
  const hours = Math.floor(min / 60);
  if (hours < 24) return { unit: "hours", n: hours };
  const days = Math.floor(hours / 24);
  if (days < 7) return { unit: "days", n: days };
  return { unit: "date", n: 0, date: Dates.isoDate(new Date(iso)) };
}
