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
	force_state(State.hit)


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
