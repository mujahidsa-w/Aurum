extends RefCounted
## Google sign-in settings.
## Create an OAuth client in Google Cloud Console -> APIs & Services -> Credentials ->
## "Create credentials" -> "OAuth client ID" -> type "TVs and Limited Input devices",
## then paste its client ID and secret here. Until then the login screen offers guest play.

const CLIENT_ID := "YOUR_CLIENT_ID.apps.googleusercontent.com"
const CLIENT_SECRET := "YOUR_CLIENT_SECRET"
const SCOPES := "openid email profile"


static func is_configured() -> bool:
	return not CLIENT_ID.begins_with("YOUR_") and not CLIENT_SECRET.begins_with("YOUR_")
