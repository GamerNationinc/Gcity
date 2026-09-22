## Prints what the pinned GodotSteam binding sees on this machine: whether the
## extension loaded, whether the Steam client is up and logged on, the app id, the
## action sets and the connected controllers. Run after upgrading the pin
## (docs/dependencies.md) and for the G5 evidence package.
##   godot --headless --path . -s tools/steam_probe.gd
extends SceneTree


func _initialize() -> void:
	var host: SteamHost = SteamHost.new()
	root.add_child(host)
	print("extension loaded: %s" % Engine.has_singleton("Steam"))
	print("status: %s" % host.status())
	if host.is_online():
		var steam: Object = Engine.get_singleton("Steam")
		print("persona: %s  app: %d  logged on: %s  deck: %s" % [host.persona(), host.app_id(), steam.call("loggedOn"), host.is_deck()])
		print("action sets resolved: %s  cloud enabled: %s  overlay enabled: %s" % [host.has_action_sets(), host.cloud_enabled(), steam.call("isOverlayEnabled")])
		print("controllers: %s" % [steam.call("getConnectedControllers")])
	quit(0)
