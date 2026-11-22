class_name ActorHealth
extends Node
## Hit points, stagger and the rule that decides what zero HP means:
##   • civilians, students, protesters, patients: knocked out (they get up later)
##   • Syndicate members: downed, waiting for the player's choice (arrest / finish / spare)
## Nobody dies from ordinary damage. Death only follows an explicit choice to finish someone.

signal changed(hp: float, max_hp: float)
signal downed
signal recovered

var max_hp := 100.0
var hp := 100.0
var armor := 0.0            # 0..1 damage reduction (boss paper armour, guards' vests)
var poise := 30.0           # stagger threshold
var _poise := 30.0
var is_down := false
var down_time := 0.0
var recover_after := 25.0   # KO'd civilians get up after this many seconds
var can_recover := true

func setup(max_health: float, armour: float = 0.0) -> void:
	max_hp = max_health
	hp = max_health
	armor = armour

## Returns true if the hit staggered the actor.
func damage(amount: float) -> bool:
	if is_down:
		return false
	var dmg := amount * (1.0 - armor)
	hp = maxf(0.0, hp - dmg)
	changed.emit(hp, max_hp)
	_poise -= dmg
	var stagger := _poise <= 0.0
	if stagger:
		_poise = poise
	if hp <= 0.0:
		is_down = true
		down_time = 0.0
		downed.emit()
	return stagger

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	changed.emit(hp, max_hp)

func _process(delta: float) -> void:
	_poise = minf(poise, _poise + delta * 6.0)
	if is_down:
		down_time += delta
		if can_recover and down_time > recover_after:
			is_down = false
			hp = max_hp * 0.4
			changed.emit(hp, max_hp)
			recovered.emit()
