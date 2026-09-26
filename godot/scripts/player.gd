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
