# Anatomy

The two complete scripts, and the scene wiring that carries them.

## Scene tree

Both characters use the same shape.

```
Player                       CharacterBody2D, the script, the machine
├── CollisionShape2D
└── Directional              Node2D, flipped to face left or right
    └── AnimatedSprite2D     holds the sprite strips
        └── AnimationPlayer  holds one animation per enum key
```

`Directional` exists so facing left flips the sprite and everything parented to it
(weapons, hitboxes) in one move, without touching the body's collision shape.

The AnimationPlayer sits **under** the AnimatedSprite2D. Its `root_node` defaults to
`..`, so track paths resolve against the sprite: `.:animation` picks the strip,
`.:frame` picks the frame, and `../..` reaches the character body for method tracks.

Nodes are wired with `@export` slots and asserted in `_ready`, as `godot-code-style`
requires. The `.tscn` node line carries `node_paths=PackedStringArray("directional",
"animation")`; without it the slots read back `null` after `instantiate()`.

## Input-driven character

`scripts/player.gd`

```gdscript
class_name Player extends CharacterBody2D
# Input-driven character. The whole state machine is the enum, BLOCKED_STATES,
# c_state, and force_state / set_state / set_animation.

enum Direction { left = -1, right = 1 }
enum State { idle, walk, jump, fall, attack, hit }

# States that must play to the end. set_state refuses while one is current.
const BLOCKED_STATES: Array[State] = [State.attack, State.hit]

const SPEED: float = 100.0
const JUMP_VELOCITY: float = -300.0
const INVICIBILITY_TIME: float = 0.5

@export_category("Nodes")
@export var directional: Node2D
@export var animation: AnimationPlayer

var c_direction: Direction = Direction.right
var c_state: State = State.idle
var on_floor: bool = false
var block_invicibility_time: float = 0.0


func _ready() -> void:
	assert(directional, "player.gd - @export directional is not set in the editor on: " + self.name)
	assert(animation, "player.gd - @export animation is not set in the editor on: " + self.name)

	Global.register_player(self)

	animation.play(&"idle")
	var _error: int = animation.animation_finished.connect(
		func(_anim_name: StringName) -> void: force_state(State.idle)
	)


func _physics_process(delta: float) -> void:
	on_floor = is_on_floor()
	block_invicibility_time = maxf(0.0, block_invicibility_time - delta)

	if !on_floor:
		velocity += get_gravity() * delta

	if on_floor and Input.is_action_just_pressed(&"jump"):
		velocity.y = JUMP_VELOCITY

	var axis_direction: float = Input.get_axis(&"move_left", &"move_right")
	if axis_direction > 0.0:
		set_direction(Direction.right)
	elif axis_direction < 0.0:
		set_direction(Direction.left)

	if BLOCKED_STATES.has(c_state) and on_floor:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	elif is_zero_approx(axis_direction):
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = float(c_direction) * SPEED

	# One if/elif chain, highest priority first, right before move_and_slide.
	if Input.is_action_just_pressed(&"attack"):
		attack()
	elif on_floor and !is_zero_approx(axis_direction):
		set_state(State.walk)
	elif on_floor and is_zero_approx(axis_direction):
		set_state(State.idle)
	elif !on_floor and velocity.y < 0.0:
		set_state(State.jump)
	elif !on_floor and velocity.y > 0.0:
		set_state(State.fall)

	var _collided: bool = move_and_slide()


func attack() -> void:
	set_state(State.attack)


func take_damage() -> void:
	if block_invicibility_time > 0.0:
		return
	block_invicibility_time = INVICIBILITY_TIME
	set_state(State.hit)


# Ignores BLOCKED_STATES. Only the animation_finished callback uses it.
func force_state(state: State) -> void:
	c_state = state
	set_animation()


# The normal door. Refuses while a blocked state is playing.
func set_state(state: State) -> void:
	if BLOCKED_STATES.has(c_state):
		return
	c_state = state
	set_animation()


func set_animation() -> void:
	var new_anim: StringName = State.keys()[c_state]
	assert(animation.has_animation(new_anim), "player.gd - animation player has no animation named '" + new_anim + "'")
	animation.play(new_anim)


func set_direction(direction: Direction) -> void:
	if c_direction == direction:
		return

	if direction == Direction.left:
		directional.scale.y = -1.0
		directional.rotation_degrees = 180.0
	else:
		directional.scale.y = 1.0
		directional.rotation_degrees = 0.0

	c_direction = direction
```

## Character with no input

`scripts/dummy.gd`

Two differences. `set_state` also refuses a repeat of the current state — an
early-out, not a fix (`traps.md`, trap 5). And an AnimationPlayer method track calls
`play_sfx` at the exact frame the sound belongs on, instead of the code guessing.

```gdscript
class_name Dummy extends CharacterBody2D
# No input. Same machine as player.gd, with the two differences that matter:
# set_state also refuses a repeat of the current state, and an AnimationPlayer
# method track calls play_sfx at the exact frame the sound belongs on.

enum Direction { left = -1, right = 1 }
enum State { idle, walk, hit }

const BLOCKED_STATES: Array[State] = [State.hit]

const SPEED: float = 40.0
const PATROL_HALF_WIDTH: float = 40.0

@export_category("Nodes")
@export var directional: Node2D
@export var animation: AnimationPlayer

@export_category("SFX")
@export var sfx_idle: PackedStringArray
@export var sfx_walk: PackedStringArray
@export var sfx_hit: PackedStringArray

@onready var sfx: Dictionary[State, PackedStringArray] = {
	State.idle: sfx_idle,
	State.walk: sfx_walk,
	State.hit: sfx_hit,
}

var c_direction: Direction = Direction.right
var c_state: State = State.idle
var on_floor: bool = false
var origin_x: float = 0.0

# Observable proof that the method track fired. A real game plays a sound here.
var sfx_calls: int = 0
var last_sfx: String = ""


func _ready() -> void:
	assert(directional, "dummy.gd - @export directional is not set in the editor on: " + self.name)
	assert(animation, "dummy.gd - @export animation is not set in the editor on: " + self.name)

	Global.register_dummy(self)
	origin_x = global_position.x

	animation.play(&"idle")
	var _error: int = animation.animation_finished.connect(
		func(_anim_name: StringName) -> void: force_state(State.idle)
	)


func _physics_process(delta: float) -> void:
	on_floor = is_on_floor()

	if !on_floor:
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	if global_position.x > origin_x + PATROL_HALF_WIDTH:
		set_direction(Direction.left)
	elif global_position.x < origin_x - PATROL_HALF_WIDTH:
		set_direction(Direction.right)

	if BLOCKED_STATES.has(c_state):
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = float(c_direction) * SPEED

	set_state(State.walk if !is_zero_approx(velocity.x) else State.idle)
	var _collided: bool = move_and_slide()


func take_damage() -> void:
	set_state(State.hit)


func force_state(state: State) -> void:
	c_state = state
	set_animation()


# Also refuses a repeat of the current state: an early-out, not a fix, since
# play() on the animation already playing does not restart it.
func set_state(state: State) -> void:
	if BLOCKED_STATES.has(c_state) or state == c_state:
		return
	c_state = state
	set_animation()


func set_animation() -> void:
	var new_anim: StringName = State.keys()[c_state]
	assert(animation.has_animation(new_anim), "dummy.gd - animation player has no animation named '" + new_anim + "'")
	animation.play(new_anim)


# Called from an AnimationPlayer method track, not from code.
func play_sfx() -> void:
	sfx_calls += 1
	if !sfx.has(c_state) or sfx[c_state].is_empty():
		return
	last_sfx = sfx[c_state][randi() % sfx[c_state].size()]


func set_direction(direction: Direction) -> void:
	if c_direction == direction:
		return

	if direction == Direction.left:
		directional.scale.y = -1.0
		directional.rotation_degrees = 180.0
	else:
		directional.scale.y = 1.0
		directional.rotation_degrees = 0.0

	c_direction = direction
```

## Sound per state

The dictionary maps a state to its candidate sounds. `play_sfx` reads `c_state` at
the moment the track fires, so one function covers every state.

```gdscript
@onready var sfx: Dictionary[State, PackedStringArray] = {
	State.idle: sfx_idle,
	State.walk: sfx_walk,
	State.hit: sfx_hit,
}
```

The track that calls it, inside the `hit` animation:

```ini
tracks/2/type = "method"
tracks/2/path = NodePath("../..")
tracks/2/keys = {
"times": PackedFloat32Array(0.1),
"transitions": PackedFloat32Array(1),
"values": [{
"args": [],
"method": &"play_sfx"
}]
}
```

`../..` is the character body, two levels up from the AnimationPlayer's root node.

## Direction flipping

Rotating 180 degrees and mirroring Y keeps child positions correct, where a plain
`scale.x = -1` mirrors every child transform including text and particle direction.

```gdscript
func set_direction(direction: Direction) -> void:
	if c_direction == direction:
		return

	if direction == Direction.left:
		directional.scale.y = -1.0
		directional.rotation_degrees = 180.0
	else:
		directional.scale.y = 1.0
		directional.rotation_degrees = 0.0

	c_direction = direction
```

`enum Direction { left = -1, right = 1 }` gives the enum a numeric meaning, so
`float(c_direction) * SPEED` is the velocity and no lookup table is needed.
