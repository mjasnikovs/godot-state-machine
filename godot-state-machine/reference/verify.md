# Verify

## Warnings as errors

Every GDScript warning that matters is set to `2` in `project.godot`, so a warning
stops the project from loading at all.

```ini
[debug]

gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
gdscript/warnings/unsafe_void_return=2
gdscript/warnings/return_value_discarded=2
gdscript/warnings/narrowing_conversion=2
gdscript/warnings/int_as_enum_without_cast=2
```

Three consequences you hit immediately.

- `move_and_slide()` and `Signal.connect()` return values. Prefix the call with
  `@warning_ignore("return_value_discarded")`.
- `State.keys()[c_state]` is a `Variant`. Assign it to a typed local
  (`var new_anim: StringName = ...`) before passing it anywhere.
- `c_direction * SPEED` mixes an enum with a float. Write `float(c_direction) * SPEED`.

## Running it

```sh
cd godot
godot --headless --import                          # once
godot --headless tests/verify.tscn --quit-after 400
```

Exit code 0 is a pass. The run prints every check.

```
[enum / animation contract]
  ok    Player animation 'idle' exists for State.idle
  ...
[loop modes]
  ok    blocked Player 'attack' does NOT loop (or it never ends)
  ...
PASS  41 checks, 160 physics frames, 0 failures
```

## What it proves

| Group | Checks |
|---|---|
| enum / animation contract | every key of both enums has an animation of that exact name |
| loop modes | every blocked state is non-looping, every free state loops |
| input drives the state | held input reaches `State.walk`, released input reaches `State.idle`, the playing animation equals `State.keys()[c_state]` |
| blocking | `set_state` and `take_damage` are both refused mid-attack, and the state survives to the end of the animation |
| force_state | `animation_finished` returns to idle unaided, and `force_state` overrides a blocked state |
| method track | the track fired `play_sfx`, which picked a sound from the current state's array |
| air states | jump, fall and landing each reach their state |

The contract group is the one worth stealing. It loops over `State.keys()`, so a state
added to the enum without an animation fails the test instead of crashing a player
months later.

```gdscript
for key: String in Player.State.keys():
	_check(
		"Player animation '%s' exists for State.%s" % [key, key],
		player.animation.has_animation(key)
	)
```

And the loop-mode group, which catches trap 1 before it ships.

```gdscript
for state: Player.State in Player.State.values():
	var key: String = Player.State.keys()[state]
	var anim: Animation = player.animation.get_animation(key)
	if Player.blocked_states.has(state):
		_check("blocked '%s' does NOT loop" % key, anim.loop_mode == Animation.LOOP_NONE)
	else:
		_check("free '%s' loops" % key, anim.loop_mode != Animation.LOOP_NONE)
```

## The full harness

`tests/verify.gd`

```gdscript
extends Node

## Headless self-test for the enum state machine.
##
##     godot --headless tests/verify.tscn
##
## Exit code 0 = every check passed. 1 = at least one failed.

var _failures: Array[String] = []
var _checks: int = 0
var _frame: int = 0
var _phase: String = "startup"

var _player_idle_position: float = 0.0
var _dummy_walk_position: float = 0.0
var _dummy_position_before_repeat: float = 0.0
var _dummy_position_after_repeat: float = 0.0
var _sfx_calls_before_hit: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
		return
	var line: String = label
	if not detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _check_animation_contract() -> void:
	print("\n[enum / animation contract]")

	var player: Player = Global.player
	for key: String in Player.State.keys():
		_check(
			"Player animation '%s' exists for State.%s" % [key, key],
			player.animation.has_animation(key)
		)

	var dummy: Dummy = Global.dummy
	for key: String in Dummy.State.keys():
		_check(
			"Dummy animation '%s' exists for State.%s" % [key, key],
			dummy.animation.has_animation(key)
		)

	print("\n[loop modes]")
	for state: Player.State in Player.State.values():
		var key: String = Player.State.keys()[state]
		var anim: Animation = player.animation.get_animation(key)
		var blocked: bool = Player.blocked_states.has(state)
		if blocked:
			_check(
				"blocked Player '%s' does NOT loop (or it never ends)" % key,
				anim.loop_mode == Animation.LOOP_NONE,
				str(anim.loop_mode)
			)
		else:
			_check(
				"free Player '%s' loops" % key,
				anim.loop_mode != Animation.LOOP_NONE,
				str(anim.loop_mode)
			)

	for state: Dummy.State in Dummy.State.values():
		var key: String = Dummy.State.keys()[state]
		var anim: Animation = dummy.animation.get_animation(key)
		if Dummy.blocked_states.has(state):
			_check(
				"blocked Dummy '%s' does NOT loop" % key,
				anim.loop_mode == Animation.LOOP_NONE,
				str(anim.loop_mode)
			)
		else:
			_check("free Dummy '%s' loops" % key, anim.loop_mode != Animation.LOOP_NONE)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var player: Player = Global.player
	var dummy: Dummy = Global.dummy

	match _frame:
		2:
			_check("player registered itself in Global", player != null)
			_check("dummy registered itself in Global", dummy != null)
			_check_animation_contract()
			print("\n[input drives the state]")
			_phase = "walking"
			Input.action_press("move_right")
		20:
			_check(
				"holding move_right puts the player in State.walk",
				player.c_state == Player.State.walk,
				str(Player.State.keys()[player.c_state])
			)
			_check(
				"the playing animation is State.keys()[c_state]",
				player.animation.current_animation == StringName("walk"),
				str(player.animation.current_animation)
			)
			Input.action_release("move_right")
		30:
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

			print("\n[blocking]")
			_phase = "attacking"
			player.attack()
			_check(
				"attack() enters State.attack",
				player.c_state == Player.State.attack,
				str(Player.State.keys()[player.c_state])
			)
		31:
			player.set_state(Player.State.idle)
			_check(
				"set_state is refused while a blocked state is current",
				player.c_state == Player.State.attack,
				str(Player.State.keys()[player.c_state])
			)
			player.take_damage()
			_check(
				"take_damage is swallowed during attack (it goes through set_state)",
				player.c_state == Player.State.attack,
				str(Player.State.keys()[player.c_state])
			)
		40:
			_check(
				"the blocked state is still running mid-animation",
				player.c_state == Player.State.attack,
				str(Player.State.keys()[player.c_state])
			)
		55:
			_check(
				"animation_finished force_states back to idle on its own",
				player.c_state == Player.State.idle,
				str(Player.State.keys()[player.c_state])
			)
			print("\n[force_state]")
			player.block_invicibility_time = 0.0
			player.take_damage()
			_check(
				"take_damage enters State.hit when nothing blocks it",
				player.c_state == Player.State.hit,
				str(Player.State.keys()[player.c_state])
			)
		56:
			player.force_state(Player.State.idle)
			_check(
				"force_state ignores blocked_states",
				player.c_state == Player.State.idle,
				str(Player.State.keys()[player.c_state])
			)
			_check(
				"force_state also swapped the animation",
				player.animation.current_animation == StringName("idle"),
				str(player.animation.current_animation)
			)

			print("\n[method track]")
			_phase = "dummy hit"
			_sfx_calls_before_hit = dummy.sfx_calls
			dummy.take_damage()
			_check(
				"dummy take_damage enters State.hit",
				dummy.c_state == Dummy.State.hit,
				str(Dummy.State.keys()[dummy.c_state])
			)
		72:
			_check(
				"the AnimationPlayer method track called play_sfx",
				dummy.sfx_calls > _sfx_calls_before_hit,
				"calls %d -> %d" % [_sfx_calls_before_hit, dummy.sfx_calls]
			)
			_check(
				"play_sfx picked a sound from the current state's array",
				dummy.last_sfx in dummy.sfx_hit,
				dummy.last_sfx
			)
		75:
			_check(
				"the dummy left State.hit once its animation ended",
				dummy.c_state != Dummy.State.hit,
				str(Dummy.State.keys()[dummy.c_state])
			)

			print("\n[same-state guard]")
			_phase = "same state"
			_dummy_position_before_repeat = dummy.animation.current_animation_position
		76:
			dummy.set_state(dummy.c_state)
			_dummy_position_after_repeat = dummy.animation.current_animation_position
			_check(
				"set_state(current) on the dummy leaves the position advancing",
				_dummy_position_after_repeat >= _dummy_position_before_repeat,
				"%f -> %f" % [_dummy_position_before_repeat, _dummy_position_after_repeat]
			)

			print("\n[air states]")
			_phase = "jumping"
			Input.action_press("jump")
		78:
			Input.action_release("jump")
		82:
			_check(
				"rising off the floor is State.jump",
				Global.player.c_state == Player.State.jump,
				str(Player.State.keys()[Global.player.c_state])
			)
		110:
			_check(
				"falling back down is State.fall",
				Global.player.c_state == Player.State.fall,
				str(Player.State.keys()[Global.player.c_state])
			)
		160:
			_check(
				"landing returns to State.idle",
				Global.player.c_state == Player.State.idle,
				str(Player.State.keys()[Global.player.c_state])
			)
			_report_and_quit()


func _report_and_quit() -> void:
	print("\n------------------------------------------------------------")
	if _failures.is_empty():
		print("PASS  %d checks, %d physics frames, 0 failures" % [_checks, _frame])
		get_tree().quit(0)
		return

	print("FAIL  %d failures out of %d checks (phase: %s)" % [_failures.size(), _checks, _phase])
	for failure: String in _failures:
		print("  - %s" % failure)
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
