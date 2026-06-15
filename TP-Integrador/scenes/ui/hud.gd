extends CanvasLayer

@export var weapon_texture: Texture2D

@export var fire_sound: AudioStream # Sonido del disparo. hay que ponerlo en → /audio/sfx/shot.wav.

@export_range(0.05, 1.5, 0.01) var weapon_screen_fraction := 0.33


@export var idle_sway_amp := Vector2(2.0, 1.5)   
@export var idle_sway_speed := 1.5              
@export var walk_bob_amp := Vector2(6.0, 8.0)    
@export var walk_bob_speed := 9.0                
@export var recoil_offset := Vector2(0.0, 26.0)  
@export var recoil_rotation := 0.08              

@onready var weapon: Sprite2D = $WeaponView/WeaponSprite
@onready var _crosshair_h: ColorRect = $Crosshair/H
@onready var _crosshair_v: ColorRect = $Crosshair/V
@onready var _stamina_bar: TextureProgressBar = $StaminaBar
@onready var _name_label: Label = $NameLabel
@onready var _players_label: Label = $PlayersPanel/PlayersLabel

const PLAYER_SPEED := 7.0 #==SPEED de player en player.gd

const CROSSHAIR_IDLE := Color(1, 1, 1, 0.85)
## Rojo: apuntando a un objetivo (jugador o NPC) en rango — mismo color para ambos.
const CROSSHAIR_TARGET := Color(0.95, 0.15, 0.15, 0.95)

const STAMINA_FULL := Color(1, 1, 1, 1)
const STAMINA_COOLDOWN := Color(0.7, 0.7, 0.7, 1)  # apagada mientras recarga

# Rango (frac del ancho) que ocupa el relleno amarillo interno dentro del marco,
# medido sobre stamina.png vs stamina vacia.png. Reajustar si cambia el arte.
const STAMINA_FILL_LEFT := 0.208
const STAMINA_FILL_RIGHT := 0.918

var _base_pos: Vector2
var _shot_player: AudioStreamPlayer
var _t := 0.0
var _move_blend := 0.0   
var _target_move := 0.0
var _recoil := 0.0       

func _ready() -> void:
	if weapon_texture:
		weapon.texture = weapon_texture
	_fit_weapon_to_screen()
	_base_pos = weapon.position
	_setup_fire_sound()


func _setup_fire_sound() -> void:
	if fire_sound == null and ResourceLoader.exists("res://audio/sfx/shot.wav"):
		fire_sound = load("res://audio/sfx/shot.wav")
	_shot_player = AudioStreamPlayer.new()
	_shot_player.stream = fire_sound
	add_child(_shot_player)

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
	if _shot_player and _shot_player.stream:
		_shot_player.play()

func set_target_acquired(on: bool) -> void:
	var c := CROSSHAIR_TARGET if on else CROSSHAIR_IDLE
	_crosshair_h.color = c
	_crosshair_v.color = c

## fraction 0..1; on_cooldown atenúa toda la barra mientras se recarga.
## Remapea al rango real del relleno para que vacío visual ⟺ stamina 0.
func set_stamina(fraction: float, on_cooldown: bool) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	_stamina_bar.value = lerpf(STAMINA_FILL_LEFT, STAMINA_FILL_RIGHT, f)
	_stamina_bar.self_modulate = STAMINA_COOLDOWN if on_cooldown else STAMINA_FULL

func set_players_alive(alive: int, total: int) -> void:
	_players_label.text = "%d / %d" % [alive, total]

func set_player_name(player_name: String) -> void:
	_name_label.text = player_name

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
