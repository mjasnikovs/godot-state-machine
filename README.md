# Godot State Machine

A character state machine in Godot 4 built from one enum, a blocked-states list and an
AnimationPlayer. No state nodes, no `StateMachine` class, no script per state. Godot 4.7.

Every claim in this repo was measured against the working project in `godot/`, not
copied from a tutorial. Two of them contradict advice you will find elsewhere, and
where they do, the measurement is shown.

## How it works

An enum key **is** an animation name.

```gdscript
enum State { idle, walk, jump, fall, attack, hit }


func set_animation() -> void:
	var new_anim: StringName = State.keys()[c_state]
	animation.play(new_anim)
```

One list decides which states cannot be interrupted.

```gdscript
const BLOCKED_STATES: Array[State] = [State.attack, State.hit]


func set_state(state: State) -> void:
	if BLOCKED_STATES.has(c_state):
		return
	c_state = state
	set_animation()
```

And one signal is the normal way out of them. `force_state` has two callers in game
code: that signal, and damage that must land whatever the state.

```gdscript
	var _error: int = animation.animation_finished.connect(
		func(_anim_name: StringName) -> void: force_state(State.idle)
	)
```

That is the whole machine. Adding a state is one enum key, one animation, one `elif`.

## The six traps

| # | Trap | Symptom | Fix |
|---|---|---|---|
| 1 | Blocked state with a looping animation | character frozen in that state forever | `loop_mode = 0` on every blocked state |
| 2 | `take_damage` calls `set_state` | damage taken mid-attack is silently ignored | damage that must land calls `force_state`, behind an invincibility buffer |
| 3 | Enum key with no animation | crashes the first time that state is entered, not at load | assert in `set_animation`, plus a test over `State.keys()` |
| 4 | Asserting on a method track the same tick | the call has not happened yet | the AnimationPlayer runs on the idle clock and method tracks are deferred — measured 7 physics frames late |
| 5 | Adding `state == c_state` to stop restarts | fixes nothing that was broken | `play(X)` while X already plays keeps its position — measured |
| 6 | A third caller of `force_state` | `BLOCKED_STATES` stops being a guarantee and becomes a suggestion | two callers in game code: the `animation_finished` reset and damage that must land; anything else that must interrupt a blocked state is a state that is not blocked |

Trap 1 is the one that ships. Trap 2 is the one that gets argued about.

## Run it

Needs Godot 4.7.2 or newer, and gdtoolkit 4.5.0 for `gdformat` and `gdlint`.

```sh
cd godot
godot --headless --import                             # once
godot                                                 # play
gdformat --check scripts/ tests/
gdlint scripts/ tests/
godot --headless tests/verify.tscn --quit-after 400   # silent + exit 0 = pass
```

Controls: `A`/`D` or arrows to move, `Space` to jump, `J` to attack. The blue square is
the input-driven character, the other one patrols on its own.

All 49 GDScript warnings are set to **error**, and nothing is suppressed. The scripts
follow the [godot-code-style](https://github.com/mjasnikovs/godot-code-style) skill,
with its `.gdlintrc` and `.gdformatrc`.

## Read it

- **[godot-state-machine/SKILL.md](godot-state-machine/SKILL.md)** — the whole technique in 171 lines. Start here.
- [godot-state-machine/reference/anatomy.md](godot-state-machine/reference/anatomy.md) — both full scripts, direction
  flipping, per-state sound through an animation method track, scene wiring.
- [godot-state-machine/reference/traps.md](godot-state-machine/reference/traps.md) — the measurements behind the
  table above.
- [godot-state-machine/reference/verify.md](godot-state-machine/reference/verify.md) — strict typing settings and the
  full test harness.

## Use it as an Agent Skill

`godot-state-machine/` follows the [Agent Skills](https://agentskills.io/specification)
standard. Link it into whichever agent you use:

```sh
ln -s "$PWD/godot-state-machine" ~/.claude/skills/godot-state-machine   # Claude Code
ln -s "$PWD/godot-state-machine" ~/.pi/agent/skills/godot-state-machine # pi
ln -s "$PWD/godot-state-machine" ~/.agents/skills/godot-state-machine   # shared
```

It then fires on its own when you work on a Godot character state machine. Only the
171-line `SKILL.md` sits in context; the reference files load on demand.

It is also just markdown. Read it directly if you would rather not install anything.

## License

MIT. See [LICENSE](LICENSE). The sprite in `godot/sprites/` is a generated placeholder
and carries the same license.
