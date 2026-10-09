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
