# ==== Pepper & Carrot Game ====
#
## @package player
# Player movement code
#
# ==============================
extends KinematicBody2D

var _scene_manager

const GRAVITY = 60.0
const JUMP_FORCE = 800.0

## Angle in degrees towards either side that the player can consider "floor"
const FLOOR_ANGLE_TOLERANCE = 40
const SLIDE_STOP_VELOCITY = 500.0 # One pixel per second
const SLIDE_STOP_MIN_TRAVEL = 1.0 # One pixel

const STOP_FORCE = 3000.0 # Stop force on the air and the ground
const WALK_MAX_SPEED = 600.0
const MAX_AIRBORNE_SPEED = 800.0
const WALK_FORCE = 50.0

## Not an actual jetpack, just mario styled variable jump height.
const JUMP_JETPACK_FORCE = 100.0
const MAX_JETPACK_TIME = 0.1

## Wether or not input is disabled
var input_disabled = false

## Maximum time you can be in the air and still be able to jump, save the frames and kill the animals.
const JUMP_MAX_AIRBORNE_TIME = 0.2 # 12 frames...

## Time we've been on the air
var on_air_time = 0 
## This force is applied when drifting in the air
const AIR_CONTROL_FORCE = 600

const AIR_MAX_SPEED = 100

var sprite_root

## FUCKING BIG HACK: Because godot is dumb and it sometimes fails to report a collision when checking
# is_colliding() from another node we have to have this
var is_actually_colliding = false

## Current player state
var state
## Current velocity
var velocity = Vector2()

## Next frame velocity
var new_velocity = Vector2()



## Constructor
func _ready():
	
	_scene_manager = get_node("/root/scene_manager")
	
	state = PlayerStandState.new(self)
	sprite_root = get_node("Sprite")
	var animation_player = get_node("Sprite/PepperSprite/AnimationPlayer")
	animation_player.connect("finished",self,"animation_finished")
	_scene_manager.set_player(self)
	set_fixed_process(true)


## Executes when a footstep happens
func footstep():
	var choice = round(rand_range(1,4))
	get_node("SamplePlayer").play("wdl_footstep_" + str(choice))
	
## Gets the camera.
# @return The camera node.
func get_camera():
	return get_node("Camera2D")

## Fired when the current animation is finished.
func animation_finished():
	if state.has_method("animation_finished"):
		var name = get_node("Sprite/PepperSprite/AnimationPlayer").get_current_animation()
		state.animation_finished(name)

## Sets the animation speed
# @param speed New animation speed.
func set_animation_speed(speed):
	var animation_player = get_node("Sprite/PepperSprite/AnimationPlayer")
	animation_player.set_speed(speed)

## Changes the state.
# @param new_state State to change to.
func change_state(new_state):
	if state and state.has_method("OnExit"):
		state.OnExit()
	state = new_state
	if state.has_method("OnEnter"):
		state.OnEnter()

## Adds a vector to velocity on the next frame.
# @param movement Vector3 of the new velocity
func add_movement(movement):
	new_velocity += movement

## Changes the current character animation
# @param new_animation New animation.
func change_animation(new_animation):
	var animation = get_node("Sprite/PepperSprite/AnimationPlayer").get_current_animation()
	if new_animation != animation:
		get_node("Sprite/PepperSprite/AnimationPlayer").play(new_animation)

## Used when transitioning from the main menu.
# @param to_location Objective location for the camera.
func interpolate_camera_offset(to_location):
	var tween = Tween.new()
	var camera = get_node("Camera2D")
	add_child(tween)
	tween.interpolate_method(camera, "set_offset", camera.get_offset(), to_location, 1, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tween.interpolate_callback(self, 1, "finish_interpolate_camera_offset",tween)
	tween.start()

## Deletes the tween object from memory, used as a callback from interpolate_camera_offset().
# @param tween Tween object.
func finish_interpolate_camera_offset(tween):
	tween.free()
func _fixed_process(delta):
	new_velocity = Vector2(0,GRAVITY)
	state.Update(delta)
	velocity += new_velocity 
	var motion = velocity * delta
	motion = move(motion)
	var n = get_collision_normal()
	if is_colliding():
		is_actually_colliding = true
		if state.has_method("collide"):
			state.collide()

		if new_velocity.x == 0 and get_travel().length() < SLIDE_STOP_MIN_TRAVEL and abs(velocity.x) < SLIDE_STOP_VELOCITY and get_collider_velocity() == Vector2():
			# Since this formula will always slide the character around,
			# a special case must be considered to to stop it from moving
			# if standing on an inclined floor. Conditions are:
			# 1) Standing on floor (on_air_time == 0)
			# 2) Did not move more than one pixel (get_travel().length() < SLIDE_STOP_MIN_TRAVEL)
			# 3) Not moving horizontally (abs(velocity.x) < SLIDE_STOP_VELOCITY)
			# 4) Collider is not moving

			revert_motion()
			velocity.y = 0.0
		else:

			motion = n.slide(motion)
			velocity = n.slide(velocity)
			move(motion)
	else:
		# HACK: Godot is kinda dumb sometimes.
		is_actually_colliding = false
	#DEBUG
	var game_manager = get_node("/root/game_manager")
	var animation_pos = get_node("Sprite/PepperSprite/AnimationPlayer").get_current_animation_pos()
	var animation = get_node("Sprite/PepperSprite/AnimationPlayer").get_current_animation()
	if game_manager.DEBUG:
		var text = "State: %s\nVelocity: %s Animation: %s Animation pos: %s" % [str(state.name), str(velocity), animation, str(animation_pos)]
		get_node("PlayerDebug/DebugLabel").set_text(text)

## Changes the input to enabled or disabled
# @param input_state True if input should be disabled, false if not.
func disable_input(input_state):
	input_disabled = input_state

## This is our custom function for checking if an action is pressed
# mainly to allow disable_input to actually work.
# @param action Action to check.
# @return If the action is pressed.
func custom_is_action_pressed(action):
	if not input_disabled:
		return Input.is_action_pressed(action)
	else:
		return false
		
## Gets the joy axis status
# @param controller Controller number to check.
# @param axis Axis to check.
# @return Value of input on axis, 0 if input is disabled.
func custom_joy_axis(controller, axis):
	if not input_disabled:
		return Input.get_joy_axis(controller, axis)
	else:
		return 0

# ==============================
## Player state base class, controls jumping and turning around too.
# ==============================
class PlayerState:
	## If the player can turn around or not
	var can_turn_around = true
	## If the player can jump
	var can_jump = true
	## If walk_left is being pressed
	var walk_left = false
	## If walk right is being pressed.
	var walk_right = false
	
	## Value of input, when using keyboard this is either -+1 or 0, but when using joystick it can be other values
	# for throttling the speed down
	var walk_input_value = null
	
	## Name of the state for the debugger
	var name = "PlayerState"
	
	## Player object
	var player = null
	
	## Minimum joystick input
	const JOYSTICK_MIN = 0.1
	
	## Constructor
	# @param player player object
	func _init(player):
		self.player = player
		
	## Update function, should be called once each frame
	# @param delta Delta time.
	func Update(delta):
		self.walk_left = player.custom_is_action_pressed("left")
		self.walk_right = player.custom_is_action_pressed("right")
		var axis = player.custom_joy_axis(0, JOY_AXIS_0)
		self.walk_input_value = 1

		if abs(axis) > JOYSTICK_MIN:
			if axis > 0:
				self.walk_right = true
			else:
				self.walk_left = true
			self.walk_input_value = abs(axis)
		var jump = player.custom_is_action_pressed("jump")
		# Sprite turnaround, player can turn around in the air, but should she be able to?
		if can_turn_around:
			if walk_left:
				player.sprite_root.set_scale(Vector2(-1,1))
			elif walk_right:
				player.sprite_root.set_scale(Vector2(1,1))
		if jump and can_jump:
			player.velocity.y = -player.JUMP_FORCE
			player.change_state(player.PlayerJumpState.new(player))
			return

# ==============================
## Standard state for all ground based states, handles leaving the ground 
#
# inherits: PlayerState
# ==============================
class PlayerGroundState:
	extends PlayerState
	func _init(player).(player):
		player.on_air_time = 0
		pass
	func Update(delta):
		.Update(delta)

		if not player.is_actually_colliding:
			# Make sure the player can still jump for a while before officially leaving the ground.
			player.on_air_time += delta
			if player.on_air_time > player.JUMP_MAX_AIRBORNE_TIME:
				player.change_state(player.PlayerFallState.new(player))

# ==============================
## Player standing state, makes sure the player stops when not running and handles starting to run.
#
# inherits: PlayerGroundState
# ==============================
class PlayerStandState:
	extends PlayerGroundState

	func _init(player).(player):
		name = "PlayerStandState"

	func collide():
		pass

	func Update(delta):
		.Update(delta)
		player.change_animation("idle")
		# Stopping shit
		var vsign = sign(player.velocity.x)
		var vlen = abs(player.velocity.x)
		vlen -= player.STOP_FORCE*delta
		if vlen < 0:
			vlen = 0
		player.velocity.x= vlen*vsign

		if walk_left or walk_right:
			player.change_state(player.PlayerWalkState.new(player))


# ==============================
## Player walking, makes sure the player never goes over the maximum walking speed.
#
# inherits: PlayerGroundState
# ==============================
class PlayerWalkState:
	extends PlayerGroundState
	func _init(player).(player):
		name="PlayerWalkState"
	func Update(delta):
		.Update(delta)
		player.change_animation("walk")
		var jump = player.custom_is_action_pressed("jump")

		# Actual max speed
		var defacto_max_walk_speed = player.WALK_MAX_SPEED*walk_input_value
		# Velocity modifier
		var modifier = 1.0
		# This modifier is applied when turning around
		var turnaround_modifier = 10.0

		if walk_left:
			if player.velocity.x > 0:
				modifier = turnaround_modifier
			else:
				modifier = 1.0
			if player.velocity.x >= -defacto_max_walk_speed:
					player.add_movement(Vector2(-player.WALK_FORCE*walk_input_value*modifier,0))

		elif walk_right:
			if player.velocity.x < 0:
				modifier = turnaround_modifier
			else:
				modifier = 1.0
			if not player.velocity.x >= defacto_max_walk_speed:
				player.add_movement(Vector2(player.WALK_FORCE*walk_input_value*modifier,0))
		else:
			player.change_state(player.PlayerStandState.new(player))

		if abs(player.velocity.x) > defacto_max_walk_speed:
			# This makes sure 100% that the player never goes past the expected maximum speed
			# It has some issues like the player being able to get up to 50 units of speed more
			# In some circumstances, even if it should never happen.
			# This is needed because when sliding down ramps the player just kept getting more speed
			# And we don't want that do we?
			var abv = abs(player.velocity.x)
			var vsign = sign(player.velocity.x)
			var difference = defacto_max_walk_speed-abv
			player.add_movement(Vector2((vsign)*difference, 0))
		player.set_animation_speed(walk_input_value*3)
	func OnExit():
		player.set_animation_speed(1)
# ==============================
## Unused state, originally meant for landing animation
# but having a landing animation that can't be cancelled
# in a singleplayer game is dumb, plus even if we could cancel
# the animation we had to slow the speed so that it looked right
# which is a PITA for bunny hopping
#
# inherits: PlayerGroundState
# ==============================
class PlayerLandState:
	extends PlayerGroundState
	func _init(player).(player):
		name = "PlayerLandState"
		pass
	func OnEnter():
		player.change_animation("land")
	func Update(delta):
		.Update(delta)
		var jump = player.custom_is_action_pressed("jump")
		var vsign = sign(player.velocity.x)
		var vlen = abs(player.velocity.x)
		vlen -= player.STOP_FORCE*delta
		if vlen < 0:
			vlen = 0
		player.velocity.x= vlen*vsign
		if jump:
			player.velocity.x = player.velocity.x*4
	func animation_finished(name):
		if name == "land":
			player.change_state(player.PlayerStandState.new(player))

# ==============================
## Handles aerial control shenanigans and handles landing
#
# inherits: PlayerState
# ==============================
class PlayerFallState:
	extends PlayerState

	func _init(player).(player):
		name = "PlayerFallState"
		can_jump=false
	func OnEnter():
		player.change_animation("fall")
	func Update(delta):
		.Update(delta)
		var vsign = sign(player.velocity.x)
		# Try to slow the character down if he's too fast.
		if abs(player.velocity.x) > player.MAX_AIRBORNE_SPEED:
			player.velocity.x = player.MAX_AIRBORNE_SPEED*vsign
		# This code ensures we don't add more velocity if the speed is bigger than it should be
		# However if the player gets speed in any other way this won't limit it
		# This is a HACK, but it should work... right?
		if walk_left:
			if player.velocity.x > -player.AIR_MAX_SPEED:
				player.add_movement(Vector2(-player.AIR_CONTROL_FORCE,0))
		elif walk_right:
			if player.velocity.x < player.AIR_MAX_SPEED:
				player.add_movement(Vector2(player.AIR_CONTROL_FORCE,0))

	func collide():
		# Ran against something, is it the floor? Get normal
		var n = player.get_collision_normal()

		if rad2deg(acos(n.dot(Vector2(0, -1)))) < player.FLOOR_ANGLE_TOLERANCE:
			# If angle to the "up" vectors is < angle tolerance
			# char is on floor
			player.change_state(player.PlayerStandState.new(player))

# ==============================
## Handles jump animation and jetpack.
# The player used to get a small boost at the start of this state
# however this is not necessary anymore since air acceleration is
# so high bunnyhopping is already very easy to do and be useful,
# for you, speedrunners.
#
# inherits: PlayerFallState
# ==============================
class PlayerJumpState:
	extends PlayerFallState
	var can_jetpack = true
	var jetpack_delta = 0
	func _init(player).(player):
		name = "PlayerJumpState"
	func Update(delta):
		.Update(delta)
		var jump = player.custom_is_action_pressed("jump")
		if not jump:
			can_jetpack = false
		else:
			if can_jetpack:
				player.add_movement(Vector2(0,-player.JUMP_JETPACK_FORCE))
				jetpack_delta = jetpack_delta + delta
				if jetpack_delta > player.MAX_JETPACK_TIME:
					can_jetpack = false
		player.change_animation("p_jump")
	func animation_finished(name):
		if name == "p_jump":
			player.change_state(player.PlayerFallState.new(player))
