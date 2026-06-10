extends CanvasLayer

@export var weapon_texture: Texture2D

@export_range(0.05, 1.5, 0.01) var weapon_screen_fraction := 0.33


@export var idle_sway_amp := Vector2(2.0, 1.5)   
@export var idle_sway_speed := 1.5              
@export var walk_bob_amp := Vector2(6.0, 8.0)    
@export var walk_bob_speed := 9.0                
@export var recoil_offset := Vector2(0.0, 26.0)  
@export var recoil_rotation := 0.08              

@onready var weapon: Sprite2D = $WeaponView/WeaponSprite

const PLAYER_SPEED := 7.0 #==SPEED de player en plager.gd

var _base_pos: Vector2
var _t := 0.0
var _move_blend := 0.0   
var _target_move := 0.0
var _recoil := 0.0       

func _ready() -> void:
	if weapon_texture:
		weapon.texture = weapon_texture
	_fit_weapon_to_screen()
	_base_pos = weapon.position

func _fit_weapon_to_screen() -> void:
	if weapon.texture == null:
		return
	var tex := weapon.texture.get_size()
	if tex.x <= 0.0:
		return
	var screen_w := get_viewport().get_visible_rect().size.x
	var s := (screen_w * weapon_screen_fraction) / tex.x
	weapon.scale = Vector2(s, s)
	weapon.position = Vector2(0.0, -tex.y * s * 0.5)

func set_moving(speed: float) -> void:
	_target_move = clampf(speed / PLAYER_SPEED, 0.0, 1.0)

func play_fire() -> void:
	_recoil = 1.0

func _process(delta: float) -> void:
	_t += delta
	_move_blend = lerpf(_move_blend, _target_move, clampf(delta * 8.0, 0.0, 1.0))
	_recoil = lerpf(_recoil, 0.0, clampf(delta * 10.0, 0.0, 1.0))

	var sway := Vector2(
		sin(_t * idle_sway_speed) * idle_sway_amp.x,
		sin(_t * idle_sway_speed * 2.0) * idle_sway_amp.y
	)
	var bob := Vector2(
		sin(_t * walk_bob_speed) * walk_bob_amp.x,
		absf(sin(_t * walk_bob_speed)) * walk_bob_amp.y
	) * _move_blend

	weapon.position = _base_pos + sway + bob + recoil_offset * _recoil
	weapon.rotation = recoil_rotation * _recoil
