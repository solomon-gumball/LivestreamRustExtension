class_name Util

static func get_all_children_recursive(node: Node) -> Array[Node]:
    var children: Array[Node] = []
    for child in node.get_children():
        children.append(child)
        children += get_all_children_recursive(child)
    return children

static func json_string_to_class(json_string: String, _class: Object) -> Object:
    var parse_result: Variant = JSON.parse_string(json_string)
    if !parse_result.error:
        return json_to_class(parse_result.result, _class)
    return _class

static func json_to_class(json: Dictionary, _class: Object) -> Object:
    var properties: Array = _class.get_property_list()
    for key in json.keys():
        for property in properties:
            if property.name == key and property.usage >= (1 << 13):
                if (property["class_name"] in ["Reference", "Object"] and property["type"] == 17):
                    _class.set(key, json_to_class(json[key], _class.get(key)))
                else:
                    _class.set(key, json[key])
                break
            if key == property.hint_string and property.usage >= (1 << 13):
                if (property["class_name"] in ["Reference", "Object"] and property["type"] == 17):
                    _class.set(property.name, json_to_class(json[key], _class.get(key)))
                else:
                    _class.set(property.name, json[key])
                break
    return _class

static func class_to_json_string(_class: Object) -> String:
    return JSON.stringify(class_to_json(_class))

static func class_to_json(_class: Object) -> Dictionary:
    var dictionary: Dictionary = {}
    var properties: Array = _class.get_property_list()
    for property in properties:
        if not property["name"].is_empty() and property.usage >= (1 << 13):
            if (property["class_name"] in ["Reference", "Object"] and property["type"] == 17):
                dictionary[property.name] = class_to_json(_class.get(property.name))
            else:
                dictionary[property.name] = _class.get(property.name)
        if not property["hint_string"].is_empty() and property.usage >= (1 << 13):
            if (property["class_name"] in ["Reference", "Object"] and property["type"] == 17):
                dictionary[property.hint_string] = class_to_json(_class.get(property.name))
            else:
                dictionary[property.hint_string] = _class.get(property.name)
    return dictionary

# Enum for axis specification
enum Axis { FORWARD, RIGHT, UP }

# Function to create a Basis from a normal and an axis
static func basis_from_axis(normal: Vector3, axis: Axis) -> Basis:
    if normal.length_squared() < 1e-6:
        return Basis()  # Avoid zero vectors

    var normalized_normal = normal.normalized()
    var secondary: Vector3
    var tertiary: Vector3

    match axis:
        Axis.FORWARD:
            secondary = Vector3.UP if abs(normalized_normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
        Axis.RIGHT:
            secondary = Vector3.UP if abs(normalized_normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
        Axis.UP:
            secondary = Vector3.FORWARD if abs(normalized_normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT

    tertiary = normalized_normal.cross(secondary).normalized()
    secondary = tertiary.cross(normalized_normal).normalized()

    if tertiary.length_squared() < 1e-6 or secondary.length_squared() < 1e-6:
        return Basis()  # Fallback if still invalid

    match axis:
        Axis.FORWARD:
            return Basis(tertiary, secondary, -normalized_normal)
        Axis.RIGHT:
            return Basis(normalized_normal, secondary, tertiary)
        Axis.UP:
            return Basis(tertiary, normalized_normal, secondary)

    return Basis()  # Default fallback
