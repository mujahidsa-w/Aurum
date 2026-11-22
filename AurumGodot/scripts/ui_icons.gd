extends RefCounted
## Vector icons and banner artwork for the lobby UI.
## Everything is plain SVG rasterised at runtime, so there are no image files to import
## and icons stay crisp at any resolution.

const HEAD := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>"
const TAIL := "</svg>"

const ICONS := {
	"crown": "<path d='M6 22 L19 34 L32 12 L45 34 L58 22 L52 48 H12 Z' fill='#FFC21A' stroke='#A86F00' stroke-width='3' stroke-linejoin='round'/><rect x='12' y='51' width='40' height='7' rx='2' fill='#FFC21A' stroke='#A86F00' stroke-width='2'/><circle cx='32' cy='36' r='4' fill='#E8452E'/>",
	"person": "<circle cx='32' cy='20' r='12' fill='#FFFFFF'/><path d='M9 58 C9 41 19 35 32 35 C45 35 55 41 55 58 Z' fill='#FFFFFF'/>",
	"plus": "<path d='M32 10 V54 M10 32 H54' stroke='#FFFFFF' stroke-width='8' stroke-linecap='round'/>",
	"flag": "<path d='M13 7 V58' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round'/><path d='M16 9 H46 L39 19 L46 29 H16 Z' fill='#FFFFFF'/><circle cx='46' cy='40' r='6.5' fill='#FFFFFF'/><path d='M33 60 C33 51 39 48.5 46 48.5 C53 48.5 59 51 59 60 Z' fill='#FFFFFF'/>",
	"cloud": "<path d='M18 46 C9 46 6 39 8.5 33.5 C10.5 28.5 15.5 27 19 28 C21 19 29 15 36 16.5 C42 18 46 23 47 28.5 C54 28.5 58 33 58 38.5 C58 43 54.5 46 49.5 46' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round' stroke-linejoin='round'/><path d='M32 54 V32 M24 40 L32 31.5 L40 40' fill='none' stroke='#FFFFFF' stroke-width='4.5' stroke-linecap='round' stroke-linejoin='round'/>",
	"notice": "<path d='M7 41 C7 24 18 13 31 13 C44 13 53 23 53 37 V41 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M3 43 H57' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round'/><path d='M14 47 H48 L44 55 H18 Z' fill='none' stroke='#FFFFFF' stroke-width='3.5' stroke-linejoin='round'/><path d='M18 30 H44' stroke='#FFFFFF' stroke-width='3' stroke-linecap='round'/><path d='M52 18 L61 19.5 L56 44 L50.5 43 Z' fill='#FFC21A'/><circle cx='52.5' cy='52' r='4.5' fill='#FFC21A'/>",
	"bag": "<path d='M11 22 H53 L49 58 H15 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M23 27 V18 C23 12 27 8 32 8 C37 8 41 12 41 18 V27' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round'/>",
	"coin": "<circle cx='32' cy='32' r='28' fill='#E3A100'/><circle cx='32' cy='32' r='22' fill='#FFD54A' stroke='#B97C00' stroke-width='3'/><path d='M41 25.5 C39 21 35.5 19 31 19 C24 19 19.5 24.5 19.5 32 C19.5 39.5 24.5 45 31.5 45 C37.5 45 42 41 42 34 H32.5' fill='none' stroke='#8F5B00' stroke-width='5.5' stroke-linecap='round' stroke-linejoin='round'/>",
	"gem": "<path d='M11 24 L21 9 H43 L53 24 L32 57 Z' fill='#41CFFF' stroke='#0B6FA8' stroke-width='3' stroke-linejoin='round'/><path d='M11 24 H53 M21 9 L26 24 L32 57 M43 9 L38 24 L32 57 M26 24 L32 9 L38 24' fill='none' stroke='#0B6FA8' stroke-width='2' stroke-linejoin='round'/><path d='M23 13 L20 21' stroke='#FFFFFF' stroke-width='3' stroke-linecap='round' opacity='0.8'/>",
	"pass": "<path d='M32 4 L56 18 V46 L32 60 L8 46 V18 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M19 24 L32 32 L45 24 M19 35 L32 43 L45 35' fill='none' stroke='#FFC21A' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>",
	"chest": "<path d='M8 28 H56 V55 H8 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M8 28 C8 16 17 11 32 11 C47 11 56 16 56 28' fill='none' stroke='#FFFFFF' stroke-width='4'/><path d='M8 37 H26 M38 37 H56' stroke='#FFFFFF' stroke-width='3.5'/><rect x='26' y='30' width='12' height='14' rx='2' fill='#FFFFFF'/>",
	"cart": "<path d='M3 10 H13 L21 42 H50 L57 19 H17' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round' stroke-linejoin='round'/><circle cx='25' cy='52' r='5' fill='#FFFFFF'/><circle cx='47' cy='52' r='5' fill='#FFFFFF'/><path d='M51 2 L53.5 8 L60 10.5 L53.5 13 L51 19 L48.5 13 L42 10.5 L48.5 8 Z' fill='#FFC21A'/>",
	"chevrons": "<path d='M13 14 L31 32 L13 50 M31 14 L49 32 L31 50' fill='none' stroke='#FFC21A' stroke-width='7' stroke-linecap='round' stroke-linejoin='round'/>",
	"sale": "<path d='M5 33 L30 8 H57 V35 L32 60 Z' fill='#FFFFFF' stroke='#123E86' stroke-width='3' stroke-linejoin='round'/><circle cx='47' cy='18' r='4' fill='#123E86'/><circle cx='26' cy='31' r='4.5' fill='none' stroke='#E8452E' stroke-width='3.5'/><circle cx='38' cy='43' r='4.5' fill='none' stroke='#E8452E' stroke-width='3.5'/><path d='M23 46 L41 28' stroke='#E8452E' stroke-width='4' stroke-linecap='round'/>",
	"gift": "<rect x='7' y='24' width='50' height='12' rx='2' fill='#FFFFFF'/><rect x='11' y='36' width='42' height='22' rx='2' fill='#FFFFFF'/><rect x='28.5' y='24' width='7' height='34' fill='#E8452E'/><path d='M32 24 C25 11 13 13 17 21 C19 24 26 24 32 24 C38 24 45 24 47 21 C51 13 39 11 32 24 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><circle cx='52' cy='12' r='3' fill='#FFC21A'/><circle cx='9' cy='14' r='2.5' fill='#FFC21A'/>",
	"squad": "<circle cx='32' cy='18' r='9' fill='#FFFFFF'/><path d='M17 54 C17 39 24 32 32 32 C40 32 47 39 47 54 Z' fill='#FFFFFF'/><circle cx='13' cy='24' r='7' fill='#FFFFFF'/><path d='M1 52 C1 42 6 36 13 36 C16 36 18 37 19.5 38.5 C16.5 42.5 15 47 15 52 Z' fill='#FFFFFF'/><circle cx='51' cy='24' r='7' fill='#FFFFFF'/><path d='M63 52 C63 42 58 36 51 36 C48 36 46 37 44.5 38.5 C47.5 42.5 49 47 49 52 Z' fill='#FFFFFF'/>",
	"play": "<path d='M16 8 L52 32 L16 56 Z' fill='#141414'/>",
	"globe": "<circle cx='32' cy='32' r='26' fill='none' stroke='#FFFFFF' stroke-width='4'/><ellipse cx='32' cy='32' rx='11' ry='26' fill='none' stroke='#FFFFFF' stroke-width='3.5'/><path d='M6 32 H58 M10 19 H54 M10 45 H54' stroke='#FFFFFF' stroke-width='3.5'/>",
	"signal": "<rect x='6' y='44' width='9' height='13' rx='1.5' fill='#FFFFFF'/><rect x='20' y='34' width='9' height='23' rx='1.5' fill='#FFFFFF'/><rect x='34' y='22' width='9' height='35' rx='1.5' fill='#FFFFFF'/><rect x='48' y='9' width='9' height='48' rx='1.5' fill='#FFFFFF' opacity='0.35'/>",
	"chat": "<path d='M7 11 H57 V44 H31 L18 56 V44 H7 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M17 23 H47 M17 32 H38' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round'/>",
	"smile": "<circle cx='32' cy='32' r='26' fill='none' stroke='#FFFFFF' stroke-width='4'/><circle cx='23' cy='26' r='4' fill='#FFFFFF'/><circle cx='41' cy='26' r='4' fill='#FFFFFF'/><path d='M19 38 C24 48 40 48 45 38' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linecap='round'/>",
	"download": "<path d='M32 6 V40 M18 27 L32 41 L46 27' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/><path d='M10 51 H54' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round'/>",
	"caret_up": "<path d='M12 42 L32 22 L52 42' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"close": "<path d='M15 15 L49 49 M49 15 L15 49' stroke='#FFFFFF' stroke-width='7' stroke-linecap='round'/>",
	"trophy": "<path d='M18 8 H46 V26 C46 36 40 42 32 42 C24 42 18 36 18 26 Z' fill='#FFC21A'/><path d='M18 14 H8 C8 26 14 30 20 30 M46 14 H56 C56 26 50 30 44 30' fill='none' stroke='#FFC21A' stroke-width='4'/><rect x='28' y='42' width='8' height='8' fill='#D99A12'/><rect x='18' y='50' width='28' height='8' rx='2' fill='#FFC21A'/>",
	"lock": "<rect x='12' y='28' width='40' height='30' rx='4' fill='#FFFFFF'/><path d='M20 28 V20 C20 13 25 8 32 8 C39 8 44 13 44 20 V28' fill='none' stroke='#FFFFFF' stroke-width='5'/><circle cx='32' cy='42' r='4' fill='#222222'/>",
	"shield": "<path d='M32 5 L54 13 V31 C54 45 44 54 32 59 C20 54 10 45 10 31 V13 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/><path d='M22 32 L29 39 L43 24' fill='none' stroke='#FFC21A' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>",
	"wrench": "<path d='M40 6 C33 6 28 12 29 19 L8 40 C5 43 5 48 8 51 L13 56 C16 59 21 59 24 56 L45 35 C52 36 58 31 58 24 L50 30 L42 28 L40 20 L46 12 C44 7 42 6 40 6 Z' fill='none' stroke='#FFFFFF' stroke-width='4' stroke-linejoin='round'/>",
	"star": "<path d='M32 5 L39.5 23 L59 24.5 L44 37 L48.5 56 L32 46 L15.5 56 L20 37 L5 24.5 L24.5 23 Z' fill='#FFC21A' stroke='#A86F00' stroke-width='2.5' stroke-linejoin='round'/>",
	"rifle": "<path d='M4 30 H14 L18 26 H44 V24 H50 V27 H60 V31 H50 V34 H40 L37 42 H31 L33 34 H26 L24 46 H16 L18 36 L4 38 Z' fill='#FFFFFF'/>",
}

const PASS_ART := "<svg xmlns='http://www.w3.org/2000/svg' width='378' height='150' viewBox='0 0 378 150'><defs><linearGradient id='bg' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#22285F'/><stop offset='0.5' stop-color='#6A45AE'/><stop offset='1' stop-color='#F0A92E'/></linearGradient><radialGradient id='glow' cx='0.74' cy='0.42' r='0.55'><stop offset='0' stop-color='#FFE9A8' stop-opacity='0.9'/><stop offset='1' stop-color='#FFE9A8' stop-opacity='0'/></radialGradient><linearGradient id='gold' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#FFF3B8'/><stop offset='0.45' stop-color='#E8B03A'/><stop offset='1' stop-color='#8F600E'/></linearGradient><linearGradient id='steel' x1='0' y1='0' x2='1' y2='0'><stop offset='0' stop-color='#9FB2D4'/><stop offset='0.5' stop-color='#EEF4FF'/><stop offset='1' stop-color='#8295BA'/></linearGradient><linearGradient id='shade' x1='0' y1='0' x2='0' y2='1'><stop offset='0.55' stop-color='#000000' stop-opacity='0'/><stop offset='1' stop-color='#000000' stop-opacity='0.55'/></linearGradient></defs><rect width='378' height='150' fill='url(#bg)'/><rect width='378' height='150' fill='url(#glow)'/><path d='M280 64 L180 0 H218 Z M280 64 L252 0 H288 Z M280 64 L330 0 H366 Z M280 64 L378 34 V70 Z' fill='#FFFFFF' opacity='0.12'/><path d='M38 150 L112 30 L124 36 L56 150 Z' fill='url(#steel)'/><path d='M96 22 C104 8 126 4 140 14 C128 18 122 28 122 40 C114 30 104 26 96 22 Z' fill='url(#steel)' stroke='#5A6C92' stroke-width='2'/><path d='M101 40 L137 58' stroke='#E8B03A' stroke-width='7' stroke-linecap='round'/><path d='M243 82 C220 72 210 54 213 37 C225 53 236 59 248 63 Z M317 82 C340 72 350 54 347 37 C335 53 324 59 312 63 Z' fill='url(#gold)' stroke='#6B4A0C' stroke-width='2'/><path d='M238 150 C232 112 240 62 280 40 C320 62 328 112 322 150 Z' fill='url(#gold)' stroke='#6B4A0C' stroke-width='3'/><path d='M280 44 V150' stroke='#FFF3B8' stroke-width='3' opacity='0.7'/><path d='M252 93 H308 L301 104 H259 Z' fill='#1E1203'/><path d='M280 40 C272 22 280 7 302 3 C291 16 293 28 287 44 Z' fill='#E8452E'/><path d='M262 120 H298' stroke='#6B4A0C' stroke-width='3' stroke-linecap='round'/><path d='M200 28 L203 36 L211 39 L203 42 L200 50 L197 42 L189 39 L197 36 Z M352 96 L354 101 L359 103 L354 105 L352 110 L350 105 L345 103 L350 101 Z' fill='#FFF3B8'/><rect width='378' height='150' fill='url(#shade)'/></svg>"

const EVENT_ART := "<svg xmlns='http://www.w3.org/2000/svg' width='262' height='96' viewBox='0 0 262 96'><defs><linearGradient id='s' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#4E9BE0'/><stop offset='1' stop-color='#F4C77C'/></linearGradient><linearGradient id='g' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#FFE38A'/><stop offset='1' stop-color='#C8861A'/></linearGradient><linearGradient id='d' x1='0' y1='0' x2='0' y2='1'><stop offset='0.45' stop-color='#000000' stop-opacity='0'/><stop offset='1' stop-color='#000000' stop-opacity='0.6'/></linearGradient></defs><rect width='262' height='96' fill='url(#s)'/><circle cx='150' cy='26' r='14' fill='#FFF4C8' opacity='0.85'/><path d='M0 66 L40 44 L72 58 L110 34 L150 56 L190 40 L230 58 L262 46 V96 H0 Z' fill='#6F8C68'/><path d='M0 80 L50 64 L100 76 L160 62 L220 78 L262 68 V96 H0 Z' fill='#3D5A3B'/><g transform='translate(196 22)'><path d='M8 0 H44 V20 C44 32 36 38 26 38 C16 38 8 32 8 20 Z' fill='url(#g)' stroke='#8F5B00' stroke-width='2'/><path d='M8 6 H0 C0 18 6 22 12 22 M44 6 H52 C52 18 46 22 40 22' fill='none' stroke='#E0A52A' stroke-width='4'/><rect x='22' y='38' width='8' height='8' fill='#B97C00'/><rect x='12' y='46' width='28' height='8' rx='2' fill='url(#g)'/><path d='M26 10 L28.5 16 L35 16.5 L30 20.5 L31.5 27 L26 23.5 L20.5 27 L22 20.5 L17 16.5 L23.5 16 Z' fill='#FFF6D0'/></g><rect x='176' y='14' width='6' height='3' fill='#E8452E' transform='rotate(30 179 15)'/><rect x='250' y='30' width='6' height='3' fill='#41CFFF' transform='rotate(-25 253 31)'/><rect x='186' y='62' width='5' height='3' fill='#FFFFFF' transform='rotate(60 188 63)'/><rect x='244' y='8' width='5' height='3' fill='#FFC21A' transform='rotate(15 246 9)'/><rect width='262' height='96' fill='url(#d)'/></svg>"

static var _cache := {}


## Returns an icon texture rendered at `px` pixels.
static func icon(name: String, px: int = 64) -> Texture2D:
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var body: String = ICONS.get(name, "")
	var tex := svg_texture(HEAD + body + TAIL, float(px) / 64.0)
	_cache[key] = tex
	return tex


## Rasterises an SVG string into a mipmapped texture.
static func svg_texture(svg: String, scale: float = 1.0) -> Texture2D:
	var img := Image.new()
	var err := img.load_svg_from_string(svg, scale)
	if err != OK or img.is_empty():
		push_warning("Could not rasterise SVG icon.")
		img = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
