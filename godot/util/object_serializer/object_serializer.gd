class_name ObjectSerializer
extends Node
## Main godot-object-serializer class. Stores the script registry.
## [url]https://github.com/Cretezy/godot-object-serializer[/url]

## The field containing the type in serialized object values. Not recommended to change.
##
## This should be set to something unlikely to clash with keys in objects/dictionaries.
##
## This can be changed, but must be configured before any serialization or deserialization.
static var type_field := "._type"

## The field containing the constructor arguments in serialized object values. Not recommended to change.
##
## This should be set to something unlikely to clash with keys in objects.
##
## This can be changed, but must be configured before any serialization or deserialization.
static var args_field := "._"

## The prefix for object types stored in [member type_field]. Not recommended to change.
##
## This should be set to something unlikely to clash with built-in type names.
##
## This can be changed, but must be configured before any serialization or deserialization.
static var object_type_prefix := "Object_"

## By default, variables with [@GlobalScope.PROPERTY_USAGE_SCRIPT_VARIABLE] are serialized (all variables have this by default).
## When [member require_export_storage] is true, variables will also require [@GlobalScope.PROPERTY_USAGE_STORAGE] to be serialized.
## This can be set on variables using [annotation @GDScript.@export_storage]. Example: [code]@export_storage var name: String[/code]
static var require_export_storage := false

## Registry of object types
static var _script_registry: Dictionary[String, _ScriptRegistryEntry]


## Registers a script (an object type) to be serialized/deserialized. All custom types (including nested types) must be registered [b]before[/b] using this library.
## [param name] can be empty if script uses [code]class_name[/code] (e.g [code]ObjectSerializer.register_script(Data)[/code]), but it's generally better to set the name.
## Nested custom types referenced by typed properties are registered automatically.
static func register_script(script: Script, script_name: StringName = "") -> void:
	var class_map: Dictionary[String, String] = {}
	for cls in ProjectSettings.get_global_class_list():
		class_map[cls["class"]] = cls["path"]
	_register_script_recursive(script, script_name, class_map)


static func _register_script_recursive(script: Script, script_name: StringName, class_map: Dictionary) -> void:
	var resolved_name := _get_script_name(script, script_name)
	assert(resolved_name, "Script must have name\n" + script.source_code)
	var type_key := object_type_prefix + resolved_name
	if _script_registry.has(type_key):
		return
	var entry := _ScriptRegistryEntry.new()
	entry.script_type = script
	entry.type = type_key
	_script_registry[type_key] = entry
	for property: Dictionary in script.get_script_property_list():
		if property.type == TYPE_OBJECT and not (property.class_name as String).is_empty():
			var cls_name: String = property.class_name
			if class_map.has(cls_name):
				_register_script_recursive(load(class_map[cls_name]), "", class_map)
	for constant_name: StringName in script.get_script_constant_map():
		var value: Variant = script.get_script_constant_map()[constant_name]
		if value is Script:
			_register_script_recursive(value, constant_name, class_map)


## Registers multiple scripts (object types) to be serialized/deserialized from a dictionary.
## See [method ObjectSerializer.register_script]
static func register_scripts(scripts: Dictionary[String, Script]) -> void:
	for script_name: StringName in scripts:
		register_script(scripts[script_name], script_name)


static func _get_script_name(script: Script, script_name: StringName = "") -> StringName:
	if script_name:
		return script_name
	if script.resource_name:
		return script.resource_name
	if script.get_global_name():
		return script.get_global_name()
	return ""


static func _get_entry(entry_name: StringName = "", script: Script = null) -> _ScriptRegistryEntry:
	if entry_name:
		var entry: _ScriptRegistryEntry = _script_registry.get(entry_name)
		if entry:
			return entry

	if script:
		for i: String in _script_registry:
			var entry: _ScriptRegistryEntry = _script_registry.get(i)
			if entry:
				if script == entry.script_type:
					return entry

	return null


class _ScriptRegistryEntry:
	var type: String
	var script_type: Script

	func serialize(value: Variant, next: Callable) -> Variant:
		if value.has_method("_serialize"):
			var result: Dictionary = value._serialize(next)
			result[ObjectSerializer.type_field] = type
			return result

		var result := {ObjectSerializer.type_field: type}

		var excluded_properties: Array[String] = []
		if value.has_method("_get_excluded_properties"):
			excluded_properties = value._get_excluded_properties()

		var partial: Dictionary = {}
		if value.has_method("_serialize_partial"):
			partial = value._serialize_partial(next)

		for property: Dictionary in value.get_property_list():
			if (
				property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
				and (
					!ObjectSerializer.require_export_storage
					or property.usage & PROPERTY_USAGE_STORAGE
				)
				and !excluded_properties.has(property.name)
				and !partial.has(property.name)
			):
				result[property.name] = next.call(value.get(property.name))

		for key: String in partial:
			result[key] = partial[key]

		if value.has_method("_get_constructor_args"):
			var args: Array = value._get_constructor_args()
			result[ObjectSerializer.args_field] = args

		return result

	## When [param json_keys] is enabled, attempt to convert int/float/bool string keys into values
	func deserialize(value: Variant, next: Callable, json_keys := false) -> Variant:
		if script_type.has_method("_deserialize"):
			return script_type._deserialize(value, next)

		var instance: Variant
		if value.has(ObjectSerializer.args_field):
			instance = script_type.new.callv(value[ObjectSerializer.args_field])
		else:
			instance = script_type.new()

		var excluded_properties: Array[String] = []
		if instance.has_method("_get_excluded_properties"):
			excluded_properties = instance._get_excluded_properties()

		var partial: Dictionary = {}
		if instance.has_method("_deserialize_partial"):
			partial = instance._deserialize_partial(value, next)

		for key: String in value:
			if (
				key == ObjectSerializer.type_field
				or key == ObjectSerializer.args_field
				or excluded_properties.has(key)
				or partial.has(key)
			):
				continue

			var key_value: Variant = next.call(value[key])
			match typeof(key_value):
				TYPE_DICTIONARY:
					if json_keys and instance[key].is_typed_key():
						match instance[key].get_typed_key_builtin():
							TYPE_STRING:
								instance[key].assign(key_value)
							TYPE_BOOL:
								var dict: Dictionary[bool, Variant] = {}
								for i in key_value:
									dict[i == "true"] = key_value[i]
								instance[key].assign(dict)
							TYPE_INT:
								var dict: Dictionary[int, Variant] = {}
								for i in key_value:
									dict[int(i)] = key_value[i]
								instance[key].assign(dict)
							TYPE_FLOAT:
								var dict: Dictionary[float, Variant] = {}
								for i in key_value:
									dict[float(i)] = key_value[i]
								instance[key].assign(dict)
							_:
								assert(
									false,
									"Trying to deserialize from JSON to a dictionary with non-primitive (String/int/float/bool) keys"
								)
					else:
						instance[key].assign(key_value)
				TYPE_ARRAY:
					instance[key].assign(key_value)
				_:
					instance[key] = key_value

		for key in partial:
			instance[key] = partial[key]

		return instance
