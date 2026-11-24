extends Node
## Inicio de sesion con Google (OAuth 2.0 "device flow"): funciona igual en PC y movil,
## sin plugins. El jugador abre google.com/device, escribe un codigo y acepta.
## Necesita un "OAuth client ID" de tipo "TVs and Limited Input devices" (ver README).

const DEVICE_URL := "https://oauth2.googleapis.com/device/code"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const USERINFO_URL := "https://www.googleapis.com/oauth2/v3/userinfo"
const CONFIG_PATH := "res://google_oauth.cfg"

var client_id := ""
var client_secret := ""
var flow := 0   # se incrementa al cancelar / empezar: invalida esperas antiguas


func load_config() -> bool:
	var cf := ConfigFile.new()
	if cf.load(CONFIG_PATH) != OK:
		return false
	client_id = str(cf.get_value("google", "client_id", "")).strip_edges()
	client_secret = str(cf.get_value("google", "client_secret", "")).strip_edges()
	return client_id != "" and not client_id.begins_with("PEGA_")


func cancel() -> void:
	flow += 1


# ---------------------------------------------------------------- peticiones HTTP
func _request(url: String, method: int, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"code": 0, "json": {}}
	var res: Array = await http.request_completed
	http.queue_free()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	var code := int(res[1]) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0
	return {"code": code, "json": parsed if parsed is Dictionary else {}}


func _post_form(url: String, fields: Dictionary) -> Dictionary:
	var body := HTTPClient.new().query_string_from_dict(fields)
	return await _request(url, HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), body)


func _err_text(r: Dictionary) -> String:
	if int(r["code"]) == 0:
		return "No hay conexión con Google"
	var j: Dictionary = r["json"]
	var msg := str(j.get("error_description", j.get("error", "Error %d" % int(r["code"]))))
	return "Google: " + msg


# ---------------------------------------------------------------- flujo
func request_device_code() -> Dictionary:
	flow += 1
	var my := flow
	var r: Dictionary = await _post_form(DEVICE_URL, {"client_id": client_id, "scope": "openid email profile"})
	var j: Dictionary = r["json"]
	if int(r["code"]) != 200 or not j.has("device_code"):
		return {"error": _err_text(r), "_flow": my}
	j["_flow"] = my
	return j


## Espera a que el jugador confirme en Google. Devuelve {"sub","name","given_name","email"...},
## {"error": texto} o {"cancelled": true}.
func poll_for_token(info: Dictionary) -> Dictionary:
	var my := int(info.get("_flow", -1))
	var interval := float(info.get("interval", 5))
	var deadline := Time.get_ticks_msec() + int(float(info.get("expires_in", 1800)) * 1000.0)
	while my == flow and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(interval).timeout
		if my != flow:
			break
		var r: Dictionary = await _post_form(TOKEN_URL, {
			"client_id": client_id,
			"client_secret": client_secret,
			"device_code": str(info["device_code"]),
			"grant_type": "urn:ietf:params:oauth:grant-type:device_code",
		})
		if my != flow:
			break
		var j: Dictionary = r["json"]
		if int(r["code"]) == 200 and j.has("access_token"):
			return await _get_userinfo(str(j["access_token"]))
		var e := str(j.get("error", ""))
		if e == "authorization_pending" or int(r["code"]) == 0:
			continue
		if e == "slow_down":
			interval += 5.0
			continue
		if e == "access_denied":
			return {"error": "Has cancelado el acceso con Google"}
		if e == "expired_token":
			return {"error": "El código ha caducado, inténtalo de nuevo"}
		return {"error": _err_text(r)}
	if my != flow:
		return {"cancelled": true}
	return {"error": "El código ha caducado, inténtalo de nuevo"}


func _get_userinfo(token: String) -> Dictionary:
	var r: Dictionary = await _request(USERINFO_URL, HTTPClient.METHOD_GET,
		PackedStringArray(["Authorization: Bearer " + token]), "")
	var j: Dictionary = r["json"]
	if int(r["code"]) != 200 or not j.has("sub"):
		return {"error": _err_text(r)}
	return j
