# Traps

Every number below was produced by running the project in `godot/` under Godot
4.7.2 headless, not read from a tutorial.

## 1. A blocked state with a looping animation freezes the character

`animation_finished` never fires for a looping animation. The reset that leaves a
blocked state is `force_state` called from that signal. So a blocked state whose
animation loops is a one-way door; only damage that must land still gets through.

Nothing in the editor warns about it. The test checks it instead:

```gdscript
	for state: Player.State in Player.State.values():
		var key: StringName = Player.State.keys()[state]
		var anim: Animation = player.animation.get_animation(key)
		if Player.BLOCKED_STATES.has(state):
			_check(
				"blocked Player '%s' does NOT loop (or it never ends)" % key,
				anim.loop_mode == Animation.LOOP_NONE,
				str(anim.loop_mode)
			)
		else:
			_check("free Player '%s' loops" % key, anim.loop_mode != Animation.LOOP_NONE, str(anim.loop_mode))
```

## 2. A blocked state swallows damage

`take_damage` ends in `set_state(State.hit)`. `set_state` refuses while `attack` is
current. So damage taken mid-attack changes nothing — no hit animation, no flash, and
whatever else `take_damage` did before that line already happened.

Measured: `attack()` on one frame, `take_damage()` on the next, `c_state` is still
`State.attack`.

This is the design working, not a bug. It is what makes an attack feel committed. If
one specific source of damage must always land, that caller uses `force_state`. It is
the second of the two callers allowed (trap 6).

## 3. A missing animation crashes on entry, not on load

`State.keys()[c_state]` is a string lookup at runtime. Add a state to the enum,
forget the animation, and the project loads, runs, and dies the first time anything
reaches that state.

The `assert` in `set_animation` turns the crash into a readable message. It does not
make it earlier. Only a test that loops over `State.keys()` does that — see
`verify.md`.

## 4. Method tracks are late

An AnimationPlayer defaults to `callback_mode_process = IDLE` and
`callback_mode_method = DEFERRED`.

```
callback_mode_process=1  (IDLE=1 PHYSICS=0)
callback_mode_method=0   (DEFERRED=0 IMMEDIATE=1)
```

So the animation clock is not the physics clock, and a method key is queued rather
than called.

Measured: a `play_sfx` key at `t = 0.1` on a state entered from `_physics_process`
fired **7 physics frames** later. At 60 Hz the key itself is 6 frames in.

Nothing to fix in the game — a sound one frame late is a sound on time. It only
matters in a test, where asserting on the effect the same tick reads as a failure.
Give it a margin.

## 5. `play()` on the animation already playing does not restart it

The `state == c_state` early-out in the no-input character looks like it exists to
stop a looping walk animation being restarted from frame 0 every physics tick.

It does not, because that never happens.

Measured, with `play(&"attack")` called on every one of 12 consecutive physics frames:

```
repeated play('attack') position after 12 frames: 0.19327444444444 / length 0.3
```

The position kept advancing. Switching away and back is what restarts it:

```
play('idle') then play('attack') position: 0.0
```

So both variants of `set_state` are correct. Add `state == c_state` to skip redundant
work, leave it out to keep the function to one rule. The input-driven character in
this project leaves it out, and its idle animation runs normally.

## 6. force_state has exactly two callers

The `animation_finished` reset, and damage that must land whatever the state. That is
`godot-code-style`'s rule (`reference/naming.md`).

The moment a third caller uses `force_state`, `BLOCKED_STATES` stops being a
guarantee and becomes a suggestion. Reviewing the machine is then a search across the
whole codebase instead of reading one file. Anything else that must interrupt a
blocked state is better modelled as a state that is not blocked.
