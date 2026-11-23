extends RefCounted
## Firebase project used for accounts, cloud saves, player IDs, friends and presence.
## These web keys identify the project; access is protected by Authentication + the
## Realtime Database rules in firebase/database.rules.json (see README).

const API_KEY := "AIzaSyBithXc9Zl3DYNldAOi20AupBAGnjMAQao"
const PROJECT_ID := "ms-company-e7166"
const AUTH_DOMAIN := "ms-company-e7166.firebaseapp.com"
const DATABASE_URL := "https://ms-company-e7166-default-rtdb.europe-west1.firebasedatabase.app"
const STORAGE_BUCKET := "ms-company-e7166.firebasestorage.app"
const APP_ID := "1:400730863326:web:ec5490c7b26120cf12744f"


static func is_configured() -> bool:
	return API_KEY != "" and DATABASE_URL.begins_with("https://")
