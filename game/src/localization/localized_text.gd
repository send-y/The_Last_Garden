class_name LocalizedText
extends RefCounted

const TEXT_KEY_FIELD: String = "text_key"
const TEXT_ARGS_FIELD: String = "text_args"
const TEXT_KEYS_FIELD: String = "text_keys"
const SEPARATOR_FIELD: String = "separator"


static func resolve(message_key: String, message_args: Dictionary = {}) -> String:
	if message_key.is_empty():
		return ""

	var resolved_args: Dictionary = {}
	for argument_variant: Variant in message_args.keys():
		var argument_name: String = String(argument_variant)
		resolved_args[argument_name] = _resolve_argument(message_args[argument_variant])
	return String(TranslationServer.translate(message_key)).format(resolved_args)


static func text_reference(text_key: String, text_args: Dictionary = {}) -> Dictionary:
	return {
		TEXT_KEY_FIELD: text_key,
		TEXT_ARGS_FIELD: text_args.duplicate(true),
	}


static func text_reference_list(text_keys: Array[String], separator: String = ", ") -> Dictionary:
	return {
		TEXT_KEYS_FIELD: text_keys.duplicate(),
		SEPARATOR_FIELD: separator,
	}


static func _resolve_argument(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return value

	var descriptor: Dictionary = value as Dictionary
	if descriptor.has(TEXT_KEY_FIELD):
		var nested_args: Dictionary = {}
		var nested_args_value: Variant = descriptor.get(TEXT_ARGS_FIELD, {})
		if typeof(nested_args_value) == TYPE_DICTIONARY:
			nested_args = nested_args_value as Dictionary
		return resolve(String(descriptor.get(TEXT_KEY_FIELD, "")), nested_args)

	if descriptor.has(TEXT_KEYS_FIELD):
		var translated_parts: PackedStringArray = []
		var keys_value: Variant = descriptor.get(TEXT_KEYS_FIELD, [])
		if typeof(keys_value) == TYPE_ARRAY:
			for key_variant: Variant in keys_value as Array:
				translated_parts.append(resolve(String(key_variant)))
		return String(descriptor.get(SEPARATOR_FIELD, ", ")).join(translated_parts)

	return descriptor
