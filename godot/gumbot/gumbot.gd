extends CharacterBody3D
class_name GumBot

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite3D = %FaceSprite

@export var mail_canvas: MeshInstance3D

@export var scrolling_screen_label: Label
@export var surface_mat: ShaderMaterial

var base_meshes = [
  "Arm",
  "Body",
  "Button",
  "Circle",
  "Hand_L",
  "Hand_R",
  "HeadCapsule",
  "Leg",
  "Sphere_001",
]
var clothing_meshes_added: Array[Node3D] = []
enum BotState { StandIdle, PresentMail, Speaking, Walking, Grabbed, Gambling, Emote }
var bot_state: BotState = BotState.Walking

var chatter: Chatter = null:
  set(new_value):
    if !is_inside_tree():
      return
    var prev_chatter = chatter
    chatter = new_value
    emote = chatter.emote

    if chatter == null: return
    # scrolling_screen_label.text = "%s GUM" % new_value.balance

    # Get all sockets
    var all_skel_children = Util.get_all_children_recursive($Armature/Skeleton3D)
    var sockets: Dictionary = {}
    for child in all_skel_children:
      if child is BoneAttachment3D && child.name.ends_with("_Socket"):
        var socket_key: String = child.name.replace("_Socket", "").replace("_", ".")
        sockets[socket_key] = child

    if prev_chatter != null:
      var should_skip_outfit_update = true
      if prev_chatter.equipped.size() != chatter.equipped.size():
        should_skip_outfit_update = false
      for slot_name in prev_chatter.equipped:
        if prev_chatter.equipped.get(slot_name, "") != chatter.equipped.get(slot_name, ""):
          should_skip_outfit_update = false
      if should_skip_outfit_update:
        return

    # Load all meshes
    var loaded_mesh_files: Dictionary[String, Node3D] = {}

    for slot_name in chatter.equipped:
      var item_name = chatter.equipped[slot_name]
      if item_name != null and !item_name.is_empty():
        var name_lowered = item_name.to_lower()
        if !loaded_mesh_files.has(name_lowered):
          var clothing_node = await ImageLoader.load_wearable_asset(name_lowered)
          if clothing_node != null:
            loaded_mesh_files[name_lowered] = clothing_node.duplicate()

    for mesh_name in base_meshes:
      var mesh: MeshInstance3D = get_node("Armature/Skeleton3D/%s" % mesh_name)
      mesh.visible = true
    
    for added_mesh in clothing_meshes_added:
      added_mesh.queue_free()
    clothing_meshes_added = []

    var skeleton: Skeleton3D = $Armature/Skeleton3D
    for slot_name in chatter.equipped:
      var item_name = chatter.equipped[slot_name]
      if item_name == null: continue
      var item_info: ShopItem = WSClient.authenticated_state.get_item_info(item_name)

      if item_info != null:
        if item_info is ShopItem.WearableShopItem and loaded_mesh_files.has((item_info as ShopItem.WearableShopItem).name.to_lower()):
          var meshes_in_slot_to_hide = item_info.metadata.hide_meshes
          for mesh_name_to_hide in meshes_in_slot_to_hide:
            var mesh: MeshInstance3D = get_node("Armature/Skeleton3D/%s" % mesh_name_to_hide)
            mesh.visible = false

          var mesh_to_add: Node3D = loaded_mesh_files[item_name.to_lower()]
          # var mesh_to_add: Node3D = load("res://assets/items/meshes/%s.glb" % item_name.to_lower()).instantiate()
          var wearable_metadata = item_info.get("metadata")

          if wearable_metadata.get("mesh_type") == "skinned_mesh":
            var skinned_meshes: Array[MeshInstance3D] = []
            skinned_meshes.assign(Util.get_all_children_recursive(mesh_to_add).filter(func (child): return child is MeshInstance3D))
            for skinned_mesh in skinned_meshes:
              skinned_mesh.get_parent().remove_child(skinned_mesh)
              skeleton.add_child(skinned_mesh)
              skinned_mesh.skeleton = "../"
              skinned_mesh.position = Vector3.ZERO
              clothing_meshes_added.append(skinned_mesh)
          else:

            var attach_to := wearable_metadata.get("attach_to") as String
            if attach_to != null and !attach_to.is_empty():
              if sockets.has(attach_to):
                var socket = sockets[attach_to]

                socket.add_child(mesh_to_add)
                clothing_meshes_added.append(mesh_to_add)
                mesh_to_add.scale = Vector3(1.0, 1.0, 1.0)
                mesh_to_add.position = wearable_metadata.offset
                mesh_to_add.rotation = wearable_metadata.rotation
              else:
                print("ERROR: NO SOCKET FOR %s" % attach_to)
            else:
              # mesh_to_add.reparent(skeleton)
              skeleton.add_child(mesh_to_add)

            if wearable_metadata.mesh_type == "own_skeleton":
              for node in Util.get_all_children_recursive(mesh_to_add):
                if node is AnimationPlayer:
                  # var anim_player: AnimationPlayer = node as AnimationPlayer
                  var anims_to_play: Array[String] = []
                  anims_to_play.assign(anim_player.get_animation_list())
                  anims_to_play = anims_to_play.filter(func (anim_name: String): return anim_name.contains(item_name.to_lower()))
                  if anims_to_play.size() > 0:
                    anim_player.play(anims_to_play[0])

              pass

            mesh_to_add.position = wearable_metadata.get("offset")
            mesh_to_add.rotation = wearable_metadata.get("rotation")
        else:
          print("ERROR: NO ITEM DATA FOR %s" % item_name)

var color: Color = Color(0.5, 0.5, 0.5, 1.0):
  set(new_value):
    color = new_value
    # surface_mat.albedo_color = color
    surface_mat.set_shader_parameter("bot_color", color)

var emote: String = "":
  set(new_value):
    if new_value == "" || new_value == emote: return
    emote = new_value
    var image_tex = await ImageLoader.load_emote(emote)

    if image_tex != null:
      sprite.texture = image_tex

var shader_mat_template: ShaderMaterial = preload("res://materials/bot_mat/bot_shader_mat.tres")
var screen_mat: StandardMaterial3D = null

func _ready() -> void:
  anim_tree.tree_root = anim_tree.tree_root.duplicate()
  anim_tree.advance_expression_base_node = NodePath("../..")

var is_emoting: bool = false:
  set(new_value):
    is_emoting = new_value
    if !is_emoting:
      for system_name in spawned_systems:
        var system: GPUParticles3D = spawned_systems[system_name]
        system.emitting = false
        system.queue_free()
        spawned_systems.erase(system_name)

var spawned_systems: Dictionary[String, GPUParticles3D] = {}
func trigger_particle_system(system_name: String, offset: Vector3 = Vector3.ZERO) -> void:
  if spawned_systems.has(system_name):
    var existing_system: GPUParticles3D = spawned_systems[system_name]
    existing_system.emitting = true
    return

  var system_template: PackedScene = load("res://src/particles/%s.tscn" % system_name)
  var system_instance: GPUParticles3D = system_template.instantiate()

  add_child(system_instance)
  system_instance.position = offset
  system_instance.emitting = true
  spawned_systems[system_name] = system_instance
