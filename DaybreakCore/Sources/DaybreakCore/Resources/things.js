// things.js — Daybreak's bridge to Things 3 (JavaScript for Automation).
//
// Used by the app (via /usr/bin/osascript) and runnable by hand for testing:
//
//   osascript -l JavaScript things.js ping
//   osascript -l JavaScript things.js lists today inbox anytime upcoming
//   osascript -l JavaScript things.js get <id> [<id> ...]
//   osascript -l JavaScript things.js complete <id>
//   osascript -l JavaScript things.js move <id> today|anytime|someday|tomorrow
//   osascript -l JavaScript things.js bench          (read timings, no writes)
//   osascript -l JavaScript things.js selftest       (creates, moves, completes and deletes one test to-do)
//
// Every command prints one JSON value on stdout. Errors are thrown, so osascript
// exits non-zero and prints the message on stderr.

const LIST_IDS = {
  inbox: "TMInboxListSource",
  today: "TMTodayListSource",
  anytime: "TMNextListSource",
  upcoming: "TMCalendarListSource",
  someday: "TMSomedayListSource",
};

function things() {
  return Application("com.culturedcode.ThingsMac");
}

function safe(fn, fallback) {
  try {
    const value = fn();
    return value === undefined ? fallback : value;
  } catch (e) {
    return fallback;
  }
}

function iso(date) {
  return date ? date.toISOString() : null;
}

function list(app, key) {
  const id = LIST_IDS[key];
  if (!id) throw new Error("Unknown list: " + key);
  return app.lists.byId(id);
}

function serializeOne(todo) {
  return {
    id: todo.id(),
    name: todo.name(),
    notes: safe(() => todo.notes(), ""),
    status: safe(() => todo.status(), "open"),
    deadline: iso(safe(() => todo.dueDate(), null)),
    startDate: iso(safe(() => todo.activationDate(), null)),
    tags: safe(() => todo.tagNames(), ""),
    project: safe(() => { const p = todo.project(); return p ? p.name() : null; }, null),
    area: safe(() => { const a = todo.area(); return a ? a.name() : null; }, null),
  };
}

// Reads a whole list with one Apple event per property instead of one per to-do.
function serializeMany(todos) {
  const ids = todos.id();
  if (ids.length === 0) return [];
  const names = todos.name();
  const notes = safe(() => todos.notes(), []);
  const statuses = safe(() => todos.status(), []);
  const deadlines = safe(() => todos.dueDate(), []);
  const starts = safe(() => todos.activationDate(), []);
  const tags = safe(() => todos.tagNames(), []);
  const out = [];
  for (let i = 0; i < ids.length; i++) {
    const todo = todos[i];
    out.push({
      id: ids[i],
      name: names[i],
      notes: notes[i] || "",
      status: statuses[i] || "open",
      deadline: iso(deadlines[i] || null),
      startDate: iso(starts[i] || null),
      tags: tags[i] || "",
      project: safe(() => { const p = todo.project(); return p ? p.name() : null; }, null),
      area: safe(() => { const a = todo.area(); return a ? a.name() : null; }, null),
    });
  }
  return out;
}

function todoByID(app, id) {
  const todo = app.toDos.byId(id);
  if (!safe(() => todo.exists(), false)) throw new Error("No to-do with id " + id);
  return todo;
}

function moveTodo(app, todo, destination) {
  if (destination === "tomorrow") {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    d.setHours(0, 0, 0, 0);
    app.schedule(todo, { for: d });
  } else {
    app.move(todo, { to: list(app, destination) });
  }
}

const commands = {
  ping(app) {
    return { ok: true, version: safe(() => app.version(), null) };
  },

  lists(app, keys) {
    const result = {};
    for (const key of keys) result[key] = serializeMany(list(app, key).toDos);
    return result;
  },

  get(app, ids) {
    const result = {};
    for (const id of ids) {
      const todo = app.toDos.byId(id);
      result[id] = safe(() => todo.exists(), false) ? serializeOne(todo) : null;
    }
    return result;
  },

  complete(app, [id]) {
    todoByID(app, id).status = "completed";
    return { ok: true };
  },

  move(app, [id, destination]) {
    moveTodo(app, todoByID(app, id), destination);
    return { ok: true };
  },

  bench(app) {
    const result = {};
    for (const key of Object.keys(LIST_IDS)) {
      const start = Date.now();
      const items = serializeMany(list(app, key).toDos);
      result[key] = { count: items.length, ms: Date.now() - start };
    }
    return result;
  },

  selftest(app) {
    const steps = [];
    const step = (name, fn) => {
      const start = Date.now();
      try {
        fn();
        steps.push({ step: name, ok: true, ms: Date.now() - start });
      } catch (e) {
        steps.push({ step: name, ok: false, error: String(e) });
        throw new Error(JSON.stringify(steps));
      }
    };
    let todo;
    step("create in Inbox", () => {
      todo = app.ToDo({ name: "Daybreak self-test (safe to delete)" });
      list(app, "inbox").toDos.push(todo);
      todo = todoByID(app, todo.id());
    });
    const id = todo.id();
    step("read back", () => serializeOne(todo));
    step("move to Today", () => moveTodo(app, todo, "today"));
    step("move to Anytime", () => moveTodo(app, todo, "anytime"));
    step("schedule Tomorrow", () => moveTodo(app, todo, "tomorrow"));
    step("move to Someday", () => moveTodo(app, todo, "someday"));
    step("complete", () => { todo.status = "completed"; });
    step("delete", () => app.delete(todo));
    return { id: id, steps: steps };
  },
};

function run(argv) {
  const [command, ...args] = argv;
  const fn = commands[command];
  if (!fn) throw new Error("Unknown command: " + command);
  return JSON.stringify(fn(things(), args));
}
