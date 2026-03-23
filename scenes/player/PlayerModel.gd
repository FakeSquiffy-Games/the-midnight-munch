# PlayerModel.gd
extends Node2D
class_name PlayerModel

@export_group("Identity")
@export var species_name: String = "Unnamed Fish"

@export_group("Visuals")
@export var base_scale: float = 1.0

# References for the Player.gd to "grab"
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var mouth: MouthArea = $MouthArea
@onready var body: BodyArea = $BodyArea

func _ready():
	# Ensure hitboxes are unique so scaling one fish 
	# doesn't scale all fish of the same species
	mouth.get_node("MouthPolygon").polygon = mouth.get_node("MouthPolygon").polygon.duplicate()
	body.get_node("BodyPolygon").polygon = body.get_node("BodyPolygon").polygon.duplicate()
