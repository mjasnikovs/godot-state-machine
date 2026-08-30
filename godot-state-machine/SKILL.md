---
name: godot-state-machine
description: >
  Build or fix a character state machine in Godot 4 using one enum, a blocked-states
  list and an AnimationPlayer whose animation names are the enum keys. Use when a
  character needs states like idle/walk/jump/attack/hit; when an attack or hit
  animation is cut short, freezes the character, or swallows later input; when a
  looping animation restarts every frame; or when an animation method track fires at
  the wrong time. Triggers: state machine, enum State, blocked states, set_state,
  force_state, animation_finished, AnimationPlayer, AnimatedSprite2D, CharacterBody2D,
  animation method track.
---

# Character state machine (Godot 4)

Verified against Godot 4.7.2 by building the project and measuring the result.

No state nodes, no `StateMachine` class, no `State` scripts. One enum, one variable,
three functions, all on the character script itself. A 6-state character is about 25
lines of machine.

The machine holds one rule: **some states must play to the end.** An attack cannot be
cancelled by walking. Everything else follows from that.

## The contract

An enum key **is** an animation name. `set_animation` looks it up by string.

```gdscript
var new_anim: StringName = State.keys()[c_state]
```

Break it and nothing works. So the enum keys are lowercase, match the AnimationPlayer
exactly, and an `assert` catches a missing one the first time that state is entered.

## The parts

```gdscript
class_name Player extends CharacterBody2D

enum State {idle, walk, jump, fall, attack, hit}

## States that must play to the end. set_state refuses while one is current.
const blocked_states: Array[State] = [State.attack, State.hit]

@export var animation: AnimationPlayer

var c_state: State = State.idle
```

## The three functions

```gdscript
## Ignores blocked_states. Only the animation_finished callback uses it.
func force_state(state: State) -> void:
	c_state = state
	set_animation()


## The normal door. Refuses while a blocked state is playing.
func set_state(state: State) -> void:
	if blocked_states.has(c_state):
		return
	c_state = state
	set_animation()


func set_animation() -> void:
	var new_anim: StringName = State.keys()[c_state]
	assert(
		animation.has_animation(new_anim),
		"player.gd - animation player has no animation named '" + new_anim + "'"
	)
	animation.play(new_anim)
```

Everything that wants to change state calls `set_state`. Nothing assigns `c_state`.

`force_state` is the only way out of a blocked state, and exactly one caller uses it.

## The release valve

```gdscript
func _ready() -> void:
	animation.play("idle")
	@warning_ignore("return_value_discarded")
	animation.animation_finished.connect(func(_anim_name: StringName) -> void:
		force_state(State.idle)
	)
```

A blocked animation ends, the signal fires, `force_state` drops back to `idle`, and
`set_state` opens again. This lambda is the whole unlock mechanism.

## Loop modes are load-bearing

| State kind | `loop_mode` | Why |
|---|---|---|
| Free (`idle`, `walk`, `jump`, `fall`) | `1` | plays forever, no `animation_finished` needed |
| Blocked (`attack`, `hit`) | `0` (none) | `animation_finished` is the only unlock |

A looping animation on a blocked state freezes the character for good. Assert this in
a test rather than trusting the editor — `reference/verify.md`.

## Picking the state each frame

One `if`/`elif` chain, highest priority first, immediately before `move_and_slide`.

```gdscript
	if Input.is_action_just_pressed("attack"):
		attack()
	elif on_floor and not is_zero_approx(axis_direction):
		set_state(State.walk)
	elif on_floor and is_zero_approx(axis_direction):
		set_state(State.idle)
	elif not on_floor and velocity.y < 0.0:
		set_state(State.jump)
	elif not on_floor and velocity.y > 0.0:
		set_state(State.fall)

	@warning_ignore("return_value_discarded")
	move_and_slide()
```

A character with no input collapses the chain to one line:

```gdscript
	set_state(State.walk if not is_zero_approx(velocity.x) else State.idle)
```

Movement can read the machine back. Zero the horizontal speed while a blocked state
runs, so an attack does not slide:

```gdscript
	if blocked_states.has(c_state) and on_floor:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
```

## The five traps

Measured, not guessed. Numbers and method in `reference/traps.md`.

| # | Trap | Symptom | Fix |
|---|---|---|---|
| 1 | Blocked state with a looping animation | character frozen in that state forever | `loop_mode = 0` on every blocked state |
| 2 | `take_damage` calls `set_state` | damage taken mid-attack is silently ignored | intended; use `force_state` for damage that must land |
| 3 | Enum key with no animation | crashes the first time that state is entered, not at load | assert in `set_animation`, plus a test over `State.keys()` |
| 4 | Asserting on a method track the same tick | the call has not happened yet | AnimationPlayer runs on the **idle** clock and method tracks default to **deferred** |
| 5 | Adding `state == c_state` to stop restarts | fixes nothing that was broken | `play(X)` while X already plays keeps its position; it is an early-out, not a repair |

Trap 1 is the one that ships. Trap 2 is the one that gets argued about.

## Build order

1. Enum, `blocked_states`, `c_state`, the three functions.
2. AnimationPlayer with one animation per enum key, named identically.
3. Loop mode per the table above.
4. `animation.play("idle")` and the `animation_finished` lambda in `_ready`.
5. The `if`/`elif` chain at the end of `_physics_process`.
6. Wire nodes with `@export` node paths and assert them in `_ready`.
7. Copy the test harness from `reference/verify.md` and keep it green.

## Reference

- `reference/anatomy.md` — both full scripts, direction flipping, per-state sound
  through an AnimationPlayer method track, and the scene wiring that carries it.
- `reference/traps.md` — the measurements behind the table above.
- `reference/verify.md` — strict-typing settings and the 41-check headless harness.
