class_name DhakaDistricts
extends Node
## Authentic place data for southern Dhaka (Jatrabari / Kajla / Sontek / East Jurain), gathered from
## Banglapedia, The Daily Star, The Business Standard, mapcarta and the JICA road inventory.
## Used for signage, mission text and district-specific architecture. Coordinates are real WGS84.

const DATA := {
	"kajla": {
		"bn": "কাজলা",
		"full": "কাজলা, মাতুয়াইল / ওয়ার্ড-১২, যাত্রাবাড়ী",
		"coord": "23.71116°N 90.4435°E",
		"roads": ["কাজলা ব্রিজ", "কাজলা পাওয়ার হাউস রোড", "ডেমরা রোড", "যাত্রাবাড়ী বিশ্ব রোড", "ঢাকা–চট্টগ্রাম হাইওয়ে", "মায়ার হানিফ ফ্লাইওভার"],
		"landmarks": ["কাজলা ব্রিজ", "মাতুয়াইল মৃধা বাড়ি ওয়াটার পাম্প", "কাজলা পাওয়ার হাউস", "কাজলা কট মার্কেট", "শনির আখড়া গরু হাট", "সামাদনগর", "কুতুবখালী"],
		"shops": ["কাজলা হার্ডওয়্যার", "মাতুয়াইল ফার্মেসি", "কাজলা ব্রিজ চা স্টল", "গরু হাট ফিড মিল", "পাওয়ার হাউস কোচিং", "কবির স্টিল ফার্নিচার"],
		"arch": "ঘন বসতি, ইটের গাঁথুনি ও টিনের চাল। চারতলা ভবনে উল্লম্ব গো-খামার (মেঝেতে ছাগল, ১ম তলে গাভী, ২য় তলে বাছুর, ৩য় তলে ষাঁড়)। রাস্তা গর্তে ভরা, বর্ষায় হাঁটুজল।",
		"note": "কাজলা ব্রিজ থেকে মাতুয়াইল মৃধা বাড়ি ওয়াটার পাম্প পর্যন্ত ঈদে গরু হাট বসে (lease ৳৪.৩৫ কোটি)।",
	},
	"sontek": {
		"bn": "সনটেক",
		"full": "সনটেক, দানিয়া / যাত্রাবাড়ী, ডাককোড ১২৩৬",
		"coord": "23.706379°N 90.446757°E",
		"roads": ["সনটেক রোড ০১", "সনটেক রোড ০২", "১ নম্বর রোড", "দানিয়া রোড", "ঢাকা–চট্টগ্রাম রোড"],
		"landmarks": ["ভূঁইয়া মঞ্জিল অ্যাপার্টমেন্ট", "সনটেক সুপারমার্কেট", "অগ্রদূত বিদ্যানিকেতন হাই স্কুল", "দানিয়া কলেজ", "সনটেক সিটি জেনারেল হাসপাতাল", "জামিয়া মুহাম্মদিয়া আরাবিয়া মাদ্রাসা"],
		"shops": ["সনটেক সুপারমার্কেট", "ভূঁইয়া মঞ্জিল স্টোর", "দানিয়া বুক ডিপো", "সনটেক ফার্মেসি", "নিউ দানিয়া টেইলার্স", "সনটেক জুয়েলার্স"],
		"arch": "আবাসন প্রকল্প—মাঝারি উঁচু অ্যাপার্টমেন্ট ভবন, ভিলা ও পাশাপাশি দোকান। রাস্তা তুলনামূলক সংগঠিত, চারপাশে চলতি নির্মাণ। সুপারমার্কেট ও স্কুল কেন্দ্র।",
		"note": "সনটেক এলাকায় সুপারমার্কেটের সামনে রাস্তা—এখানকার আবাসিক প্রকল্প ও অ্যাপার্টমেন্টই এলাকার চেহারা নির্ধারণ করে।",
	},
	"jurain": {
		"bn": "পূর্ব জুরাইন",
		"full": "পূর্ব জুরাইন / মুরাদপুর / ওয়ার্ড-৫৩, ডিএসসিসি",
		"coord": "23.70°N 90.45°E (DND বাঁধের দক্ষিণে)",
		"roads": ["কমিশনার রোড", "খোর্শেদ আলী সর্দার রোড", "নুরানি মসজিদ রোড", "২৪ ফুট রোড", "মাদ্রাসা রোড", "মেডিকেল রোড", "জুরাইন রেলগেট", "চেয়ারম্যান বাড়ি", "মিষ্টির দোকান"],
		"landmarks": ["ভিক্রমপুর প্লাজা", "জাপানি বাজার", "নেরানি মসজিদ", "হাজী খোর্শেদ আলী সর্দার সড়ক (৩ কিমি)", "কুতুবখালী খাল", "শবুজবাগ খাল", "তিতাস খাল", "ডিএনডি বাঁধ", "জুরাইন রেলগেট"],
		"shops": ["মিষ্টির দোকান", "জাপানি বাজার", "ভিক্রমপুর প্লাজা", "কমিশনার রোড কিরানা", "নুরানি মসজিদ পুষ্টি", "চাব্বিশ ফুট ফার্মেসি"],
		"arch": "২০১১ সালের আদমশুমারিতে ২৭,০০০+ বাসিন্দা। কৃষিজমিতে অনুপরিকল্পিত শহর—খাল বুজিয়ে বাড়ি। রাস্তা ৬–১২ ফুট উঁচু করে বানানোয় নিচতলা আধ-পোতা, সিঁড়ির গেট বন্ধ, দেয়াল ভেঙে নতুন দরজা। সবুজবাগ/কুতুবখালী/তিতাস খাল বুজে গেছে। সারা বছর পানি জমে—অধিকাংশ বাড়ি পরিত্যক্ত, 'ভূতুড়ে' চেহারা। ডেঙ্গু মশা, নোংরা পানি, খোলা জায়গার অভাব।",
		"note": "DND বাঁধের নিচু অববাহিকা—বাইরের রাস্তা ১০ ফুট উঁচু, বর্ষায় কোমর-par্যন্ত পানি। একসময়ের ধানক্ষেত এখন ঘন বসতি।",
	},
	"jatrabari": {
		"bn": "যাত্রাবাড়ী",
		"full": "যাত্রাবাড়ী থানা, দক্ষিণ ঢাকা",
		"coord": "23.7105°N 90.4355°E",
		"roads": ["মেয়র মোহাম্মদ হানিফ ফ্লাইওভার (১১.৫ কিমি)", "ঢাকা–চট্টগ্রাম হাইওয়ে", "ঢাকা–নারায়ণগঞ্জ রোড", "সৈয়দাবাদ ব্রিজ নিউ রোড", "ডেমরা রোড", "শাহিদ ফারুকী রোড"],
		"landmarks": ["যাত্রাবাড়ী বাস টার্মিনাল (সৈয়দাবাদ)", "যাত্রাবাড়ী পার্ক", "জাতীয় মাছ বাজার", "এ.কে. হাই স্কুল অ্যান্ড কলেজ", "ড. মাহবুবুর রহমান মোল্লা কলেজ", "দানিয়া কলেজ", "বাবর মসজিদ", "মাতুয়াইল ল্যান্ডফিল"],
		"shops": ["যাত্রাবাড়ী স্টিল ফার্নিচার", "মাছ বাজার", "হানিফ ফ্লাইওভার টোল প্লাজা", "জাতীয় হোটেল", "সৈয়দাবাদ ট্রান্সপোর্ট", "কাজলা রোড হোলসেল"],
		"arch": "দক্ষিণের প্রবেশদ্বার—ভারী যান চলাচল, ইস্পাত ও ফার্নিচার শিল্প, পাইকারি বাজার, ১১.৫ কিমি ফ্লাইওভার ও তার নিচের রাস্তা। গর্ত, ট্রাফিক জ্যাম, ধুলো ও বাতাস দূষণ।",
		"note": "চারটি বিভাগ ও নারায়ণগঞ্জ থেকে ঢাকায় প্রবেশের একমাত্র রাস্তা। ফ্লাইওভার পার হতে কখনো ১–১.৫ ঘণ্টা লাগে।",
	},
}

## Authentic Dhaka vehicle designs, from UNESCO/Bangla Academy rickshaw documentation, the
## JICA Dhaka transport study, BRTA fare tables and street reporting. Used for the 3D models.
const VEHICLES := {
	"rickshaw": {
		"bn": "সাইকেল রিকশা",
		"body": "three-wheeled pedal cycle; driver pedals in front, two passengers on a bench behind",
		"hood": "rounded bamboo vault wrapped in rexine with a metal visor ('cap') at the front top; "
			+ "Lata-pata (creeper/vegetal) and Baro Chand appliqué schemes are the signature Dhaka styles",
		"art": "hand-painted aluminium back panel, bilateral tripartite composition (two peacocks flanking a "
			+ "lion head, or two birds flanking a flower/shapla water lily); film stars, Taj Mahal, Tara Mosjid, "
			+ "riverboats, rural scenes and political motifs; gold/silver medallions, crescent-and-star, "
			+ "a crown (mukut) at the top of the hood, tassels, plastic flowers and tinsel",
		"colours": "vivid red, green, yellow, blue and gold — the most elaborate folk art in Bangladesh",
		"fare": "negotiated; short local hops (a few taaka)",
		"speed": 3.4,
	},
	"cng": {
		"bn": "সিএনজি (অটো রিকশা)",
		"body": "three-wheeled auto-rickshaw, forest-green sheet-metal body, canvas roof and side curtains; "
			+ "small driver cabin in front, bench for three passengers behind; Bajaj four-stroke CNG models",
		"art": "plain green, usually dirty and dented; a meter is fitted but fares are usually negotiated; "
			+ "route/owner name painted on the rear and a small destination board up front",
		"colours": "forest green (mandatory for all Dhaka CNGs), black roof/trim, white headlamps",
		"fare": "৳40 first 2 km, ৳12 per extra km, ৳2 per minute waiting (BRTA); negotiated in practice",
		"speed": 8.5,
	},
	"bus": {
		"bn": "বাস (omnibus / mini bus)",
		"body": "10 m omni buses and 8 m minibuses on Isuzu/Hino/Tata chassis, locally built sheet-metal bodies, "
			+ "dented and brightly painted; BRTC double-deckers also run the city routes",
		"art": "elaborate hand-painted front and side panels, route boards (e.g. গুলিস্তান–যাত্রাবাড়ী–কাজলা), "
			+ "gold/silver pinstripes, flower and bird motifs, religious calligraphy",
		"colours": "bright blues, greens, reds and yellows with black window bands",
		"fare": "flat city fare, cheap mass transport",
		"speed": 7.0,
	},
}

static func vehicle_fare(kind: String, km: float, minutes: float = 0.0) -> int:
	match kind:
		"cng":
			return int(40.0 + maxf(0.0, km - 2.0) * 12.0 + minutes * 2.0)
		"rickshaw":
			return int(max(10.0, 12.0 + km * 10.0))   # negotiated, modest
	return 20

## Authentic Dhaka architectural vocabulary, from Banglapedia / The Daily Star / DOUET studies of
## Old Dhaka courtyard houses, Mughal and colonial mansions and vernacular walk-ups.
const ARCHITECTURE := {
	"walkup": "Urban-vernacular walk-up: extreme verticality, narrow street frontage, zero lot gaps, "
		+ "shop or workshop on the ground floor, entry verandah, flats above, roof terrace with water tanks. "
		+ "Floor-defining cornices/moldings at plinth, each slab and the roof; chajja sun-shades over windows.",
	"mughal": "No balconies; perforated jali marble lattice screens for ventilation + privacy; "
		+ "pointed or cusped arches (tiny inverted-crescent cusps); facade divided into vertical/horizontal "
		+ "panels; solid low parapet sloping inward; inner courtyards (public, service, private) with pillars "
		+ "that are tapered/octagonal with bell-shaped capitals.",
	"colonial": "Semi-circular arches with keystones, Greco-Roman pediments, Ionic/Corinthian columns, "
		+ "double wooden shutter doors, French windows with tinted glass, cast-iron balustrades and brackets, "
		+ "parapets with oblong/cross/circular holes, dentils and floral stucco moldings, high plinths.",
	"courtyard": "Old Dhaka mahallas: 10-12 ft wide by 80-100 ft deep plots, shop/workshop in front, "
		+ "service lane/canal behind; single-to-multi courtyard houses 2-4 storeys, rooms around an open-to-sky "
		+ "court, colonnaded verandahs, thick walls, high ceilings and ventilators for the humid climate.",
	"windows": "Blue wooden casement windows with patterned grills and wooden frames; long windows with two "
		+ "vertical partitions; jharokha-style projecting windows with latticed screens in old mansions.",
	"materials": "Load-bearing brick masonry (15-20 inch walls), lime plaster inside and out, "
		+ "wooden rafters/purlins later replaced by iron beams, mosaic or cement floors.",
}

static func district_for_style(style: String) -> String:
	match style:
		"kajla", "cattle", "powerhouse": return "kajla"
		"sontek", "housing", "apartment": return "sontek"
		"jurain", "flooded", "waterlogged": return "jurain"
		"jatrabari", "flyover", "terminal": return "jatrabari"
	return ""

static func signage(style: String) -> Array[String]:
	var id := district_for_style(style)
	if id == "" or not DATA.has(id):
		return []
	var out: Array[String] = []
	for n in (DATA[id]["shops"] as Array):
		out.append(str(n))
	for n in (DATA[id]["landmarks"] as Array):
		out.append(str(n))
	return out

static func road_names(style: String) -> Array[String]:
	var id := district_for_style(style)
	if id == "" or not DATA.has(id):
		return []
	var out: Array[String] = []
	for n in (DATA[id]["roads"] as Array):
		out.append(str(n))
	return out

static func blurb(style: String) -> String:
	var id := district_for_style(style)
	if id == "" or not DATA.has(id):
		return ""
	return str(DATA[id]["full"]) + " — " + str(DATA[id]["note"])
