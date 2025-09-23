Ghostlang MVP for embedders (what Grim needs first)

Embedding API (Zig)

Ghost.init(alloc, HostApi)

Ghost.loadModule(path_or_text, name)

Ghost.call(func, args…) -> Value|Error

Ghost.register(host_fn, name, caps) (buffer ops, keymaps, commands)

Language features (Lua-parity first)

Functions + closures, upvalues

Tables (hash + array parts), pairs, ipairs

Control flow: if/elseif/else, for, while, break

Strings, slices, utf-8 aware length/iter

Errors: error, pcall, stack traces

Modules: require("mod") with search path and cache

Stdlib (focused)

string, table, math, os.clock() (no IO by default)

editor module (when embedded): buffers, windows, keymaps, events

lsp, git, etc. live as plugins, not core

Plugins & config layout (convention over config)

~/.config/grim/
  init.gza                # user config
  plugins/
    zeke.gza
    statusline.gza
  vendor/                 # optional, resolved copies


Load order: core → init.gza → plugins/*

Hook names: on_start, on_buffer_open(buf), on_text_change(e), on_key(k, mode)

Minimal, copyable shapes
Embedding (Zig)
const ghost = @import("ghostlang");

pub fn onInit(g: *ghost.VM) !void {
    try g.registerFn("editor.echo", struct {
        pub fn call(vm: *ghost.VM, msg: ghost.Value) !ghost.Value {
            std.debug.print("{s}\n", .{try msg.asString(vm)});
            return ghost.Value.nil();
        }
    }.call, .{ .caps = .{} });
}

pub fn loadUserConfig(g: *ghost.VM) !void {
    try g.loadModuleFile("~/.config/grim/init.gza", "user/init");
    try g.callExport("user/init", "setup", .{});
}

.gza (Lua-like core, optional modern sugar)
-- init.gza
function setup()
  editor.keymap("n", "<leader>e", fn() editor.echo("hello from ghostlang!") end)
end


Modern sugar (behind a flag or pragma):

fn setup() {
  editor.keymap("n", "<leader>e", () => editor.echo("hello"));
}

Plugin hooks
module "statusline"

fn on_start() {
  editor.statusline.set("%f %l:%c %m")
}

return { on_start = on_start }

Parser/VM work breakdown (order that pays off fastest)

Parser: function decls, blocks, return, local, if/while/for, table literals, dot/index access.

VM opcodes: CLOSURE, UPVAL, JMP/TEST, INDEX/SETINDEX, CALL/CALLTAIL.

Tables: dual-part (array+hash), load factor tuning, string interning.

Errors: exceptions + protected calls; nice traces.

Modules: search path + module cache; relative requires.

Host ABI: marshaling primitives and slices; copy-on-write strings.

Stdlib: string, table, math; keep IO opts behind capabilities.

Sandbox: capability bitset per VM; deny by default.

Plugin ABI for Grim (initial set)

editor.buffer.get(id): Buffer / current()

Buffer.read(range) -> string, Buffer.apply(edits[])

editor.keymap(mode, key, fn, opts?)

editor.command(name, fn)

editor.ui.float.open(opts) -> handle (for your Claude panel)

events.on(name, fn) where names include BufOpen, BufWrite, TextChanged, LspDiag, GitStatus

Versioning & safety

Declare GLANG_ABI=1 and bump on breaking changes.

Host advertises capabilities + ABI; ghostlang refuses to load mismatched bytecode.

Bytecode cache keyed by (source hash, ABI, stdlib version, feature flags).

Roadmap (6–8 weeks realistic, parallelizable)

Week 1–2: Parser parity + core opcodes; tables & strings; basic stdlib
Week 3: Module system; errors/pcall; embedding API v0
Week 4: Editor ABI (buffer/keymap/events) and load .gza in Grim; run first plugin
Week 5: Sandbox & capabilities; perf profiling; microbenchmarks
Week 6+: LSP bindings via host, git module, package manager bootstrap, JIT experiments

Answering your meta-question

“I want projects like grim to leverage .gza and ghostlang plugins instead of Lua.”

You’re on the right track. Build ghostlang as the embeddable runtime with a stable host ABI and Lua-parity syntax, then let Grim (and anything else) pull it in. Keep the editor specifics (buffers, UI, keymaps) in host-provided modules so the language stays editor-agnostic.

If you want, I can draft:

a HOST_ABI.md for embedders (functions, types, capabilities), and

a SYNTAX_SPEC.md enumerating Lua-compatible grammar + the “modern sugar” extensions.
