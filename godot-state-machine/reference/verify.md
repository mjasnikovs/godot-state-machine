# Verify

## Warnings as errors

All 49 GDScript warnings are set to `2` in `project.godot`, so a warning stops the
project from loading at all. The block, and the lint and format configs, are
`godot-code-style`'s, copied unchanged: see its `reference/checklist.md`.

Three consequences you hit immediately.

- `move_and_slide()` returns `bool` and `Signal.connect()` returns `int`. Keep each in
  a typed `_`-prefixed throwaway: `var _collided: bool = move_and_slide()`,
  `var _error: int = animation.animation_finished.connect(...)`. Nothing is
  suppressed.
- `State.keys()[c_state]` is a `Variant`. Assign it to a typed local
  (`var new_anim: StringName = ...`) before passing it anywhere.
- `c_direction * SPEED` mixes an enum with a float. Write `float(c_direction) * SPEED`.

## Running it

```sh
cd godot
godot --headless --import                     # once
godot --headless tests/verify.tscn --quit-after 400
```

A pass prints nothing: the harness runs 44 checks over 160 physics frames and quits
itself with exit 0. A failure prints each failed check to stderr and exits 1.

`--quit-after` counts main-loop iterations, and a pass ends at iteration 386, measured
on 4.7.2 headless. If the engine quits first, `_exit_tree` prints the frame and phase
it reached and exits 1, so a budget too small to finish cannot pass in silence.

```
FAIL  player registered itself in Global
FAIL  1 failures out of 44 checks (phase: jumping)
```

The gate is output and exit code together, the same one `godot-code-style` uses. A
`verify.gd` that fails to parse prints its parse error, so it fails at once even
though Godot then runs until `--quit-after`.

## What it proves

| Group | Checks |
|---|---|
| enum / animation contract | every key of both enums has an animation of that exact name |
| loop modes | every blocked state is non-looping, every free state loops |
| input drives the state | held input reaches `State.walk`, released input reaches `State.idle`, the playing animation equals `State.keys()[c_state]` |
| blocking | `set_state` is refused mid-attack, `take_damage` lands through `force_state` and is refused inside its invincibility buffer, and the blocked state survives mid-animation |
| force_state | `animation_finished` returns to idle unaided, and `force_state` overrides a blocked state |
| method track | the track fired `play_sfx`, which picked a sound from the current state's array |
| air states | jump, fall and landing each reach their state |
| compiles | every script in `scripts/` loads by path and `can_instantiate()`, reached by the main scene or not |

The contract group is the one worth stealing. It loops over `State.keys()`, so a state
added to the enum without an animation fails the test instead of crashing a player
months later.

```gdscript
	for key: StringName in Player.State.keys():
		_check("Player animation '%s' exists for State.%s" % [key, key], player.animation.has_animation(key))
```

And the loop-mode group, which catches trap 1 before it ships.

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

## The full harness

`tests/verify.gd`

```gdscript
class_name Verify extends Node
# Headless self-test for the enum state machine:
#
#     godot --headless tests/verify.tscn --quit-after 400
#
# Silent on a pass, and it quits itself with exit 0. A failed check is written
# to stderr and the exit is 1. Any output at all, a parse error included, is a
# failure.

const SCRIPTS_DIR: String = "res://scripts/"

var _failures: Array[String] = []
var _checks: int = 0
var _frame: int = 0
var _phase: String = "startup"
var _finished: bool = false

var _player_idle_position: float = 0.0
var _dummy_walk_position: float = 0.0
var _dummy_position_before_repeat: float = 0.0
var _dummy_position_after_repeat: float = 0.0
var _sfx_calls_before_hit: int = 0


# The main scene loads only the scripts it reaches. Loading each one by path, with
# the autoload registered, is what catches one nothing else loads.
func _ready() -> void:
	var dir: DirAccess = DirAccess.open(SCRIPTS_DIR)
	assert(dir, "verify.gd - cannot open " + SCRIPTS_DIR)
	for file_name: String in dir.get_files():
		if !file_name.ends_with(".gd"):
			continue
		var script: GDScript = load(SCRIPTS_DIR + file_name)
		_check("script compiles: " + file_name, script != null and script.can_instantiate())


func _physics_process(_delta: float) -> void:
	_frame += 1
	var player: Player = Global.player
	var dummy: Dummy = Global.dummy

	if _frame == 2:
		_check("player registered itself in Global", player != null)
		_check("dummy registered itself in Global", dummy != null)
		_check_animation_contract()
		_phase = "walking"
		Input.action_press(&"move_right")
	elif _frame == 20:
		_check(
			"holding move_right puts the player in State.walk",
			player.c_state == Player.State.walk,
			str(Player.State.keys()[player.c_state])
		)
		_check(
			"the playing animation is State.keys()[c_state]",
			player.animation.current_animation == &"walk",
			str(player.animation.current_animation)
		)
		Input.action_release(&"move_right")
	elif _frame == 30:
		_check(
			"releasing input returns the player to State.idle",
			player.c_state == Player.State.idle,
			str(Player.State.keys()[player.c_state])
		)
		_player_idle_position = player.animation.current_animation_position
		_dummy_walk_position = dummy.animation.current_animation_position
		_check(
			"a repeated set_state(idle) each tick does not restart the animation",
			_player_idle_position > 0.05,
			"position %f" % _player_idle_position
		)
		_check(
			"the dummy's same-state guard leaves its walk animation running",
			_dummy_walk_position > 0.05,
			"position %f" % _dummy_walk_position
		)

		_phase = "attacking"
		player.attack()
		_check(
			"attack() enters State.attack",
			player.c_state == Player.State.attack,
			str(Player.State.keys()[player.c_state])
		)
	elif _frame == 31:
		player.set_state(Player.State.hit)
		_check(
			"set_state is refused while a blocked state is current",
			player.c_state == Player.State.attack,
			str(Player.State.keys()[player.c_state])
		)
		player.take_damage()
		_check(
			"take_damage lands mid-attack (it goes through force_state)",
			player.c_state == Player.State.hit,
			str(Player.State.keys()[player.c_state])
		)
	elif _frame == 36:
		_check(
			"the blocked state is still running mid-animation",
			player.c_state == Player.State.hit,
			str(Player.State.keys()[player.c_state])
		)
	elif _frame == 55:
		_check(
			"animation_finished force_states back to idle on its own",
			player.c_state == Player.State.idle,
			str(Player.State.keys()[player.c_state])
		)
		player.take_damage()
		_check(
			"take_damage is refused while invincibility_buffer_time runs",
			player.c_state == Player.State.idle,
			"%s, buffer %f" % [Player.State.keys()[player.c_state], player.invincibility_buffer_time]
		)
		player.attack()
	elif _frame == 56:
		player.force_state(Player.State.idle)
		_check(
			"force_state ignores BLOCKED_STATES",
			player.c_state == Player.State.idle,
			str(Player.State.keys()[player.c_state])
		)
		_check(
			"force_state also swapped the animation",
			player.animation.current_animation == &"idle",
			str(player.animation.current_animation)
		)

		_phase = "dummy hit"
		_sfx_calls_before_hit = dummy.sfx_calls
		dummy.take_damage()
		_check(
			"dummy take_damage enters State.hit",
			dummy.c_state == Dummy.State.hit,
			str(Dummy.State.keys()[dummy.c_state])
		)
	elif _frame == 72:
		_check(
			"the AnimationPlayer method track called play_sfx",
			dummy.sfx_calls > _sfx_calls_before_hit,
			"calls %d -> %d" % [_sfx_calls_before_hit, dummy.sfx_calls]
		)
		_check(
			"play_sfx picked a sound from the current state's array", dummy.last_sfx in dummy.sfx_hit, dummy.last_sfx
		)
	elif _frame == 75:
		_check(
			"the dummy left State.hit once its animation ended",
			dummy.c_state != Dummy.State.hit,
			str(Dummy.State.keys()[dummy.c_state])
		)

		_phase = "same state"
		_dummy_position_before_repeat = dummy.animation.current_animation_position
	elif _frame == 76:
		dummy.set_state(dummy.c_state)
		_dummy_position_after_repeat = dummy.animation.current_animation_position
		_check(
			"set_state(current) on the dummy leaves the position advancing",
			_dummy_position_after_repeat >= _dummy_position_before_repeat,
			"%f -> %f" % [_dummy_position_before_repeat, _dummy_position_after_repeat]
		)

		_phase = "jumping"
		Input.action_press(&"jump")
	elif _frame == 78:
		Input.action_release(&"jump")
	elif _frame == 82:
		_check(
			"rising off the floor is State.jump",
			Global.player.c_state == Player.State.jump,
			str(Player.State.keys()[Global.player.c_state])
		)
	elif _frame == 110:
		_check(
			"falling back down is State.fall",
			Global.player.c_state == Player.State.fall,
			str(Player.State.keys()[Global.player.c_state])
		)
	elif _frame == 160:
		_check(
			"landing returns to State.idle",
			Global.player.c_state == Player.State.idle,
			str(Player.State.keys()[Global.player.c_state])
		)
		_report_and_quit()


# --quit-after tears the tree down without asking, so a run cut short would otherwise pass in silence.
func _exit_tree() -> void:
	if _finished:
		return
	printerr("FAIL  torn down at physics frame %d before the last check (phase: %s)" % [_frame, _phase])
	get_tree().quit(1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	printerr("FAIL  %s" % line)


func _check_animation_contract() -> void:
	var player: Player = Global.player
	for key: StringName in Player.State.keys():
		_check("Player animation '%s' exists for State.%s" % [key, key], player.animation.has_animation(key))

	var dummy: Dummy = Global.dummy
	for key: StringName in Dummy.State.keys():
		_check("Dummy animation '%s' exists for State.%s" % [key, key], dummy.animation.has_animation(key))

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

	for state: Dummy.State in Dummy.State.values():
		var key: StringName = Dummy.State.keys()[state]
		var anim: Animation = dummy.animation.get_animation(key)
		if Dummy.BLOCKED_STATES.has(state):
			_check("blocked Dummy '%s' does NOT loop" % key, anim.loop_mode == Animation.LOOP_NONE, str(anim.loop_mode))
		else:
			_check("free Dummy '%s' loops" % key, anim.loop_mode != Animation.LOOP_NONE)


func _report_and_quit() -> void:
	_finished = true
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("FAIL  %d failures out of %d checks (phase: %s)" % [_failures.size(), _checks, _phase])
	get_tree().quit(1)
```

The scene is a plain `Node` root with the real main scene instanced beside the
verifier, so the test drives the shipping scene rather than a copy.

```ini
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="main"]
[ext_resource type="Script" path="res://tests/verify.gd" id="verify"]

[node name="VerifyRoot" type="Node"]

[node name="Main" parent="." instance=ExtResource("main")]

[node name="Verifier" type="Node" parent="."]
script = ExtResource("verify")
```
