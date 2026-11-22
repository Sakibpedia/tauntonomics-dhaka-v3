#!/usr/bin/env python3
"""
generate_questions.py — builds the exam database for Taunt-o-Nomics: Dhaka.

Output: data/questions/questions.json (one array, compact keys):
  id   unique id                  cat   bangla | english | math | gk | bd | science | ict | law | mental | past
  sub  sub-topic                  d     difficulty 1–3
  q    prompt                     o     4 options            a  index of the correct option
  x    short explanation (Bengali)
  s    source: {"t": past_paper | statute | computed | curated | derived, ...}

How each kind is made accurate:
  past_paper  real BCS / BJS questions read from Professor's Job Solution, checked against the book's
              key and independently (from the earlier verified set).
  statute     section titles copied from the official bdlaws.minlaw.gov.bd pages.
  computed    maths, number series, clock angles, calendar days, letter coding: the answer is
              calculated by this script, never typed.
  curated     hand-entered facts: standard textbook knowledge only, nothing recent or disputed
              (no current office-holders, no contested "longest/highest" records).
  derived     spelling items built from a curated list of correct spellings; the distractors are
              deliberate corruptions, filtered so none equals another valid word in the list.

Usage: python generate_questions.py --out ../data/questions/questions.json
"""
from __future__ import annotations
import argparse, datetime, hashlib, json, math, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "qdata"))
from law_sections import ACTS  # noqa: E402

BN = "০১২৩৪৫৬৭৮৯"
def bn(v) -> str:
    return "".join(BN[int(c)] if c.isdigit() else c for c in str(v))

R = random.Random(2026)
ITEMS: list[dict] = []
SEEN: set[str] = set()

def add(cat, sub, d, q, correct, distractors, x="", src=None):
    opts = [str(correct)] + [str(v) for v in distractors]
    if len(set(opts)) < 4 or len(opts) < 4:
        return False
    opts = opts[:4]
    key = hashlib.md5((q + "|" + "|".join(sorted(opts))).encode()).hexdigest()
    if key in SEEN:
        return False
    SEEN.add(key)
    order = list(range(4)); R.shuffle(order)
    shuffled = [opts[i] for i in order]
    ITEMS.append({"id": f"{cat}-{len(ITEMS):05d}", "cat": cat, "sub": sub, "d": d, "q": q, "o": shuffled,
                  "a": shuffled.index(str(correct)), "x": x, "s": src or {"t": "curated"}})
    return True

def pick(pool, k, exclude):
    cand = [p for p in dict.fromkeys(pool) if p not in exclude]
    R.shuffle(cand)
    return cand[:k]

# ================================================================== PAST PAPERS
def past_papers():
    for fn in ("bcs_attack.json", "bangla_spelling.json", "legal.json"):
        d = json.load(open(os.path.join(HERE, "qdata", fn), encoding="utf-8"))
        for it in d["items"]:
            ex = it["exam"]
            src = {"t": "past_paper" if it["verification"]["status"] == "verified_past_paper" else "statute",
                   "exam": ex.get("name_bn"), "date": ex.get("date"), "qno": ex.get("question_no")}
            if "page" in it["source"]:
                src["book"] = "Professor's Job Solution"; src["page"] = it["source"]["page"]
            if "statute" in it["source"]:
                src["statute"] = it["source"]["statute"]; src["section"] = it["source"]["section"]
            cat = "past" if src["t"] == "past_paper" else "law"
            opts = it["options"]; ans = opts[it["answer"]]
            add(cat, it.get("topic", ""), 2, it["prompt"], ans, [o for o in opts if o != ans],
                it.get("explain_bn", ""), src)

# ================================================================== LAW (statute titles)
def law():
    for key, (name_en, name_bn, url, text) in ACTS.items():
        rows = [ln.split("|", 1) for ln in text.strip().splitlines()]
        titles = [t for _, t in rows]
        nums = [n for n, _ in rows]
        for n, t in rows:
            src = {"t": "statute", "statute": name_en, "section": n, "url": url}
            add("law", key, 2, f"{name_bn}-এর {bn(n)} ধারার শিরোনাম কী? (আইনের ইংরেজি পাঠ অনুযায়ী)", t, pick(titles, 3, {t}),
                f"{name_bn}, ধারা {bn(n)}: {t}", src)
            if R.random() < 0.55:
                add("law", key, 3, f"{name_bn}-এর কোন ধারায় “{t}” বিষয়ে বিধান রয়েছে?",
                    f"ধারা {bn(n)}", [f"ধারা {bn(m)}" for m in pick(nums, 3, {n})],
                    f"{name_bn}, ধারা {bn(n)}", src)

# ================================================================== MATH (computed)
def math_q():
    S = {"t": "computed"}
    for _ in range(90):  # percentage of
        p = R.choice([5, 10, 12, 15, 20, 25, 30, 40, 45, 60, 75]); n = R.choice(range(40, 1001, 20))
        ans = p * n // 100 if p * n % 100 == 0 else None
        if ans is None: continue
        add("math", "percent", 1, f"{bn(n)}-এর {bn(p)}% কত?", bn(ans), [bn(ans + d) for d in (n // 10, -n // 20 or -3, p)],
            f"{bn(n)} × {bn(p)} ÷ ১০০ = {bn(ans)}", S)
    for _ in range(80):  # cost price from selling price & profit/loss
        cp = R.choice(range(100, 2001, 50)); r = R.choice([5, 10, 15, 20, 25]); gain = R.random() < 0.6
        sp = cp * (100 + r) // 100 if gain else cp * (100 - r) // 100
        if (cp * (100 + r) if gain else cp * (100 - r)) % 100: continue
        word = "লাভ" if gain else "ক্ষতি"
        add("math", "profit_loss", 2, f"একটি দ্রব্য {bn(sp)} টাকায় বিক্রয় করায় {bn(r)}% {word} হলো। ক্রয়মূল্য কত?",
            f"{bn(cp)} টাকা", [f"{bn(v)} টাকা" for v in (sp, cp + r * 2, cp - r * 3)],
            f"ক্রয়মূল্য = বিক্রয়মূল্য × ১০০ ÷ (১০০ {'+' if gain else '−'} {bn(r)}) = {bn(cp)}", S)
    for _ in range(70):  # simple interest
        p = R.choice(range(1000, 20001, 500)); r = R.choice([4, 5, 6, 8, 10, 12]); t = R.choice([2, 3, 4, 5])
        if p * r * t % 100: continue
        i = p * r * t // 100
        add("math", "interest", 2, f"বার্ষিক {bn(r)}% সরল মুনাফায় {bn(p)} টাকার {bn(t)} বছরের মুনাফা কত?",
            f"{bn(i)} টাকা", [f"{bn(v)} টাকা" for v in (i + p // 20, i * 2, i - r * 10)],
            f"মুনাফা = {bn(p)} × {bn(r)} × {bn(t)} ÷ ১০০ = {bn(i)}", S)
    for _ in range(70):  # LCM / HCF
        a, b = R.sample(range(4, 61), 2); g = math.gcd(a, b); l = a * b // g
        if R.random() < 0.5:
            add("math", "lcm", 1, f"{bn(a)} ও {bn(b)}-এর ল.সা.গু কত?", bn(l), [bn(v) for v in (a * b if a * b != l else l + a, l + b, l * 2)], "", S)
        else:
            add("math", "hcf", 1, f"{bn(a)} ও {bn(b)}-এর গ.সা.গু কত?", bn(g), [bn(v) for v in (g + 1, g * 2 + 1, (g + 2) * 3)], "", S)
    for _ in range(70):  # time and work
        a, b = R.sample([4, 5, 6, 8, 10, 12, 15, 20, 24, 30], 2)
        num, den = a * b, a + b
        if num % den: continue
        t = num // den
        add("math", "work", 2, f"ক একটি কাজ {bn(a)} দিনে এবং খ {bn(b)} দিনে করতে পারে। দুজনে একত্রে কত দিনে কাজটি শেষ করবে?",
            f"{bn(t)} দিনে", [f"{bn(v)} দিনে" for v in ((a + b) // 2, t + 2, max(a, b) - t if max(a, b) - t not in (t,) else t + 4)],
            f"একত্রে = {bn(a)}×{bn(b)} ÷ ({bn(a)}+{bn(b)}) = {bn(t)}", S)
    for _ in range(70):  # speed distance
        v = R.choice(range(20, 91, 5)); h = R.choice([2, 3, 4, 5, 6]); d = v * h
        add("math", "speed", 1, f"ঘণ্টায় {bn(v)} কিমি বেগে চললে {bn(d)} কিমি যেতে কত ঘণ্টা লাগবে?",
            f"{bn(h)} ঘণ্টা", [f"{bn(x)} ঘণ্টা" for x in (h + 1, h + 2, max(h - 1, 1) if h > 1 else h + 3)], "", S)
    for _ in range(70):  # averages
        k = R.choice([3, 4, 5]); nums = sorted(R.sample(range(10, 100), k)); s = sum(nums)
        if s % k: continue
        avg = s // k
        add("math", "average", 1, f"{', '.join(bn(n) for n in nums)} — সংখ্যাগুলোর গড় কত?", bn(avg),
            [bn(avg + d) for d in (1, -2, 3)], "", S)
    for _ in range(60):  # linear equation
        x = R.randint(2, 20); a = R.randint(2, 9); b = R.randint(1, 30); c = a * x + b
        add("math", "algebra", 2, f"{bn(a)}x + {bn(b)} = {bn(c)} হলে x = কত?", bn(x), [bn(x + 1), bn(x - 1), bn(x + 3)], "", S)
    for _ in range(40):  # quadratic integer roots (positive)
        r1, r2 = sorted(R.sample(range(1, 10), 2)); s, p = r1 + r2, r1 * r2
        add("math", "algebra", 3, f"x² − {bn(s)}x + {bn(p)} = ০ সমীকরণের মূলদ্বয় কত?", f"{bn(r1)}, {bn(r2)}",
            [f"{bn(-r1)}, {bn(-r2)}", f"{bn(r1)}, {bn(-r2)}", f"{bn(r1 + 1)}, {bn(r2 + 1)}"], "", S)
    for n in range(5, 21):  # polygon diagonals and interior angle sum
        dg = n * (n - 3) // 2
        add("math", "geometry", 2, f"{bn(n)} বাহুবিশিষ্ট বহুভুজের কর্ণ কয়টি?", bn(dg), [bn(dg + n), bn(dg - 2), bn(n * (n - 1) // 2)],
            "কর্ণ = n(n−৩)/২", S)
        add("math", "geometry", 2, f"{bn(n)} বাহুবিশিষ্ট বহুভুজের অন্তঃকোণগুলোর সমষ্টি কত ডিগ্রি?", bn((n - 2) * 180),
            [bn((n - 1) * 180), bn(n * 180), bn((n - 3) * 180)], "সমষ্টি = (n−২) × ১৮০°", S)
    for _ in range(50):  # rectangle area/perimeter
        l, w = R.sample(range(3, 40), 2)
        add("math", "geometry", 1, f"একটি আয়তক্ষেত্রের দৈর্ঘ্য {bn(l)} মিটার ও প্রস্থ {bn(w)} মিটার। ক্ষেত্রফল কত?",
            f"{bn(l * w)} বর্গমিটার", [f"{bn(v)} বর্গমিটার" for v in (2 * (l + w), l * w + l, l * w - w)], "", S)
    for n in range(11, 60):  # squares and roots
        add("math", "arith", 1, f"√{bn(n * n)} = কত?", bn(n), [bn(n + 1), bn(n - 1), bn(n + 2)], "", S)
    for _ in range(60):  # ratio division
        a, b = R.sample(range(1, 10), 2); k = R.randint(5, 60); total = (a + b) * k
        add("math", "ratio", 2, f"{bn(total)} টাকা ক ও খ-এর মধ্যে {bn(a)} : {bn(b)} অনুপাতে ভাগ করলে ক কত পাবে?",
            f"{bn(a * k)} টাকা", [f"{bn(v)} টাকা" for v in (b * k, a * k + k, total // 2 if total // 2 != a * k else a * k + 2 * k)], "", S)
    for _ in range(50):  # ages
        f = R.randint(30, 60); s = R.randint(5, f - 20); y = R.randint(2, 10)
        add("math", "ages", 2, f"পিতার বর্তমান বয়স {bn(f)} বছর ও পুত্রের {bn(s)} বছর। {bn(y)} বছর পর তাদের বয়সের সমষ্টি কত হবে?",
            f"{bn(f + s + 2 * y)} বছর", [f"{bn(v)} বছর" for v in (f + s + y, f + s, f + s + 3 * y)], "", S)

# ================================================================== MENTAL ABILITY (computed)
def mental():
    S = {"t": "computed"}
    for _ in range(70):  # arithmetic series
        a = R.randint(1, 50); d = R.randint(2, 15); seq = [a + i * d for i in range(5)]
        add("mental", "series", 1, f"ধারাটির পরবর্তী সংখ্যা কত? {', '.join(bn(v) for v in seq)}, ?", bn(a + 5 * d),
            [bn(a + 5 * d + 1), bn(a + 6 * d), bn(a + 5 * d - 2)], f"প্রতিবার {bn(d)} করে বাড়ছে", S)
    for _ in range(40):  # geometric
        a = R.randint(1, 6); r = R.choice([2, 3, 4]); seq = [a * r ** i for i in range(4)]
        add("mental", "series", 2, f"ধারাটির পরবর্তী সংখ্যা কত? {', '.join(bn(v) for v in seq)}, ?", bn(a * r ** 4),
            [bn(a * r ** 4 + r), bn(a * r ** 3 * (r + 1)), bn(a * r ** 4 - a)], f"প্রতিবার {bn(r)} দিয়ে গুণ", S)
    for s0 in range(1, 25):  # squares series
        seq = [(s0 + i) ** 2 for i in range(4)]
        add("mental", "series", 2, f"পরবর্তী সংখ্যা: {', '.join(bn(v) for v in seq)}, ?", bn((s0 + 4) ** 2),
            [bn((s0 + 4) ** 2 + 2), bn((s0 + 3) ** 2 + s0), bn((s0 + 5) ** 2)], "ক্রমিক বর্গসংখ্যা", S)
    for h in range(1, 13):  # clock angles
        for m in (0, 15, 20, 30, 40, 45):
            ang = abs(30 * h - 5.5 * m); ang = min(ang, 360 - ang)
            if ang != int(ang): continue
            ang = int(ang)
            add("mental", "clock", 3, f"ঘড়িতে {bn(h)}টা {bn(m)} মিনিটে ঘণ্টা ও মিনিটের কাঁটার মধ্যবর্তী কোণ কত ডিগ্রি?",
                bn(ang), [bn(v) for v in ((ang + 30) % 181, abs(ang - 15) or 45, (ang + 90) % 181)], "কোণ = |৩০h − ৫.৫m|", S)
    days = ["সোমবার", "মঙ্গলবার", "বুধবার", "বৃহস্পতিবার", "শুক্রবার", "শনিবার", "রবিবার"]
    months = ["জানুয়ারি", "ফেব্রুয়ারি", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই", "আগস্ট", "সেপ্টেম্বর", "অক্টোবর", "নভেম্বর", "ডিসেম্বর"]
    for _ in range(60):  # calendar
        dt = datetime.date(R.randint(1990, 2025), R.randint(1, 12), R.randint(1, 28))
        ans = days[dt.weekday()]
        add("mental", "calendar", 3, f"{bn(dt.day)} {months[dt.month - 1]} {bn(dt.year)} তারিখ কী বার ছিল?", ans,
            pick(days, 3, {ans}), "ক্যালেন্ডার থেকে গণনা করা", S)
    words = ["CAT", "DOG", "BOOK", "LAW", "TEA", "EXAM", "CITY", "RIVER", "BOAT", "MANGO", "COURT", "JUDGE", "PAPER", "LEAK"]
    for _ in range(70):  # letter coding
        k = R.randint(1, 3); w1, w2 = R.sample(words, 2)
        enc = lambda w, s: "".join(chr((ord(c) - 65 + s) % 26 + 65) for c in w)
        add("mental", "coding", 2, f"যদি {w1} কে {enc(w1, k)} লেখা হয়, তবে {w2} কে কী লেখা হবে?", enc(w2, k),
            [enc(w2, k + 1), enc(w2, -k), enc(w2[::-1], k)], f"প্রতিটি অক্ষর {bn(k)} ঘর সামনে", S)

# ================================================================== BANGLA (curated + derived)
CORRECT_BN = """মুহূর্ত পুরস্কার পরিষ্কার উজ্জ্বল দ্বন্দ্ব ভবিষ্যৎ স্বাস্থ্য শারীরিক মনীষী পিপীলিকা নিশীথিনী উচ্ছ্বাস শ্মশান
শ্রদ্ধাঞ্জলি গীতাঞ্জলি মুমূর্ষু সমীচীন কৃতিত্ব দারিদ্র্য দৈন্য সৌজন্য সান্ত্বনা বুদ্ধিজীবী প্রাণিবিদ্যা মরীচিকা ঊর্ধ্ব ভৌগোলিক
ইতোমধ্যে সূচিপত্র সূচ্যগ্র প্রতিযোগিতা প্রজ্বলিত অদ্ভুত অভ্যন্তর আবির্ভাব আয়ত্ত উদ্ভিজ্জ ঊর্মি ঐকতান কনিষ্ঠ জ্যেষ্ঠ তৎক্ষণাৎ
ন্যূনতম পাষাণ নিপীড়িত ভাগীরথী ভুবন মনোহারিণী যশোলাভ গৃহিণী গণনা ঘ্রাণেন্দ্রিয় দুর্দশাগ্রস্ত বন্দ্যোপাধ্যায় ন্যূনাধিক প্রসারিণী
মধুসূদন সরীসৃপ শিরঃপীড়া শ্লেষ্মা সংকীর্ণমনা সন্ন্যাসী সহপাঠী সামর্থ্য স্বায়ত্তশাসন সরস্বতী হৃৎপিণ্ড হীনম্মন্যতা ঐক্য পিশাচ মুখস্থ
হরিৎ ইতঃপূর্বে কৃত্তিবাস অকালকুষ্মাণ্ড পূর্বাহ্ণ অপরাহ্ণ মধ্যাহ্ন চিহ্ন ব্রাহ্মণ আহ্বান জাহ্নবী মুখ্য ব্যাখ্যা উপর্যুক্ত আকাঙ্ক্ষা
উৎকর্ষ শুশ্রূষা ভস্মীভূত নিরহংকার দধীচি নৈর্ঋত কৌতূহল বিভীষিকা ব্যতীত অত্যধিক প্রত্যুৎপন্নমতি মরূদ্যান মন্ত্রিসভা প্রাণিজগৎ
স্বাক্ষর সাক্ষ্য স্বচ্ছ প্রোজ্জ্বল ত্রিভুজ উৎকৃষ্ট কুজ্ঝটিকা জাজ্বল্যমান দ্বিত্ব সত্ত্ব মহত্ত্ব তত্ত্ব বিদ্বান বিদুষী সমীক্ষা নির্নিমেষ দুরবস্থা
নিরীক্ষা উপলক্ষ পুণ্য শূন্য ক্ষুধার্ত সুধী মুমুক্ষু প্রত্যূষ মূর্ধন্য বৈশিষ্ট্য সৌন্দর্য ঔদার্য ধৈর্য শৌর্য দৈর্ঘ্য প্রাচুর্য ঐশ্বর্য""".split()

def corruptions(w: str) -> list[str]:
    swaps = [("ী", "ি"), ("ি", "ী"), ("ূ", "ু"), ("ু", "ূ"), ("ণ", "ন"), ("ন", "ণ"), ("ষ", "শ"), ("শ", "ষ"), ("স", "শ"),
             ("ষ্ণ", "স্ন"), ("্য", ""), ("্ব", ""), ("ৎ", "ত"), ("ঃ", ""), ("ঊ", "উ"), ("উ", "ঊ"), ("ঐ", "ও"),
             ("জ্জ্ব", "জ্জ"), ("ত্ত্ব", "ত্ব"), ("ক্ষ", "খ"), ("ঞ্জ", "ঞ্চ"), ("ং", "ঙ"), ("হ্ণ", "হ্ন"), ("হ্ন", "হ্ণ"), ("র্য", "র্জ")]
    out = []
    for a, b in swaps:
        i = w.find(a)
        while i != -1:
            inside_conjunct = len(a) == 1 and i > 0 and w[i - 1] == "্"
            v = w[:i] + b + w[i + len(a):]
            if v != w and not inside_conjunct:
                out.append(v)
            i = w.find(a, i + 1)
    for a, b in [(sw[0], sw[1]) for sw in swaps]:   # double corruption for variety
        if a in w and not (len(a) == 1 and w.find(a) > 0 and w[w.find(a) - 1] == "্"):
            v = w.replace(a, b, 1)
            for c, d in swaps:
                j = v.find(c)
                if j != -1 and c != a and not (len(c) == 1 and j > 0 and v[j - 1] == "্"):
                    v2 = v.replace(c, d, 1)
                    if v2 != w:
                        out.append(v2)
                        break
    valid = set(CORRECT_BN)
    return [o for o in dict.fromkeys(out) if o not in valid]

SYN_GROUPS = [
    ("সূর্য", "রবি ভানু তপন দিবাকর অর্ক মার্তণ্ড"), ("চাঁদ", "শশী সুধাংশু শশধর হিমাংশু চন্দ্র সুধাকর"),
    ("পানি", "বারি সলিল অম্বু নীর উদক"), ("আকাশ", "গগন অম্বর নভ ব্যোম অন্তরীক্ষ"),
    ("পৃথিবী", "ধরা বসুন্ধরা মেদিনী অবনী পৃথ্বী বসুধা"), ("সমুদ্র", "সাগর সিন্ধু পারাবার জলধি রত্নাকর অর্ণব"),
    ("বাতাস", "পবন সমীরণ অনিল বায়ু মারুত"), ("আগুন", "অনল অগ্নি পাবক বহ্নি হুতাশন"),
    ("পর্বত", "অচল অদ্রি গিরি শৈল ভূধর"), ("মেঘ", "জলদ জীমূত নীরদ বারিদ পয়োদ"),
    ("রাত", "রজনী নিশি যামিনী শর্বরী বিভাবরী"), ("নদী", "তটিনী তরঙ্গিণী প্রবাহিণী স্রোতস্বিনী"),
    ("পদ্ম", "কমল সরোজ পঙ্কজ নলিন অরবিন্দ"), ("চোখ", "চক্ষু নয়ন লোচন অক্ষি আঁখি"),
    ("ঘর", "গৃহ আলয় নিকেতন সদন ভবন"), ("স্ত্রী", "জায়া পত্নী ভার্যা দারা"), ("রাজা", "নৃপতি ভূপতি নরেশ রাজন"),
    ("বিদ্যুৎ", "তড়িৎ বিজলি সৌদামিনী দামিনী চপলা"), ("বন", "অরণ্য কানন বিপিন অটবী"),
    ("পাখি", "বিহগ খেচর পক্ষী বিহঙ্গ"), ("ফুল", "পুষ্প কুসুম প্রসূন"), ("কপাল", "ললাট ভাল"),
    ("বানর", "কপি মর্কট শাখামৃগ"), ("হাতি", "হস্তী করী গজ দন্তী মাতঙ্গ"), ("ঘোড়া", "অশ্ব ঘোটক তুরঙ্গ বাজী"),
]

ANT_BN = """আদি-অন্ত আবির্ভাব-তিরোভাব উত্থান-পতন উন্নত-অবনত ক্ষীয়মাণ-বর্ধমান কৃপণ-বদান্য জঙ্গম-স্থাবর দুর্লভ-সুলভ
নশ্বর-অবিনশ্বর প্রাচীন-নবীন বিরাগ-অনুরাগ স্বাধীন-পরাধীন হ্রস্ব-দীর্ঘ আকর্ষণ-বিকর্ষণ আস্তিক-নাস্তিক উত্তমর্ণ-অধমর্ণ
সধবা-বিধবা সুশীল-দুঃশীল স্তুতি-নিন্দা অনুকূল-প্রতিকূল আপদ-সম্পদ উৎকৃষ্ট-নিকৃষ্ট উত্তম-অধম ঐহিক-পারত্রিক কুটিল-সরল
খ্যাত-অখ্যাত গরিষ্ঠ-লঘিষ্ঠ গৌণ-মুখ্য চেতন-অচেতন জোয়ার-ভাটা তিক্ত-মিষ্ট দাতা-গ্রহীতা দিবা-রাত্রি ধনী-দরিদ্র পণ্ডিত-মূর্খ
প্রবেশ-প্রস্থান প্রসন্ন-বিষণ্ণ বন্ধুর-মসৃণ বিধি-নিষেধ ব্যষ্টি-সমষ্টি মিলন-বিরহ সংকোচ-প্রসার সংক্ষেপ-বিস্তার সদর-অন্দর
সবল-দুর্বল সাকার-নিরাকার সুপ্ত-জাগ্রত স্থূল-সূক্ষ্ম স্বকীয়-পরকীয় হর্ষ-বিষাদ শুক্ল-কৃষ্ণ লঘু-গুরু অগ্রজ-অনুজ
অতিবৃষ্টি-অনাবৃষ্টি অনুরক্ত-বিরক্ত আয়-ব্যয় আসামি-ফরিয়াদি ইষ্ট-অনিষ্ট উপকার-অপকার উদয়-অস্ত কোমল-কঠিন ক্রয়-বিক্রয়
ব্যক্ত-গূঢ় স্বদেশ-বিদেশ হ্রাস-বৃদ্ধি সুকৃতি-দুষ্কৃতি সক্রিয়-নিষ্ক্রিয় অর্থ-অনর্থ""".split()

BAGDHARA = [("অকাল কুষ্মাণ্ড", "অপদার্থ"), ("অগস্ত্য যাত্রা", "চিরদিনের জন্য প্রস্থান"), ("অমাবস্যার চাঁদ", "দুর্লভ বস্তু"),
    ("আক্কেল গুড়ুম", "হতবুদ্ধি"), ("আকাশ কুসুম", "অসম্ভব কল্পনা"), ("আদায় কাঁচকলায়", "শত্রুতা"), ("উড়ো চিঠি", "বেনামি পত্র"),
    ("কুয়োর ব্যাঙ", "সীমাবদ্ধ জ্ঞানসম্পন্ন ব্যক্তি"), ("গোবর গণেশ", "মূর্খ"), ("গোঁফ খেজুরে", "নিতান্ত অলস"),
    ("ঘোড়া রোগ", "সাধ্যের অতিরিক্ত শখ"), ("চাঁদের হাট", "আনন্দের প্রাচুর্য"), ("চোখের বালি", "চক্ষুশূল"),
    ("ঝাঁকের কই", "একই দলভুক্ত"), ("ঢাকের কাঠি", "মোসাহেব"), ("তাসের ঘর", "ক্ষণস্থায়ী বস্তু"), ("দুধের মাছি", "সুসময়ের বন্ধু"),
    ("ননীর পুতুল", "শ্রমবিমুখ"), ("পটল তোলা", "মারা যাওয়া"), ("ব্যাঙের সর্দি", "অসম্ভব ঘটনা"), ("ভিজে বিড়াল", "কপটচারী"),
    ("মণিকাঞ্চন যোগ", "উপযুক্ত মিলন"), ("রাবণের চিতা", "চির অশান্তি"), ("শিরে সংক্রান্তি", "আসন্ন বিপদ"), ("হাতের পাঁচ", "শেষ সম্বল"),
    ("কাকতালীয়", "দৈবাৎ ঘটনা"), ("খয়ের খাঁ", "চাটুকার"), ("গুড়ে বালি", "আশায় নৈরাশ্য"), ("অন্ধের যষ্টি", "একমাত্র অবলম্বন"),
    ("ডুমুরের ফুল", "অদৃশ্য বস্তু"), ("জিলাপির প্যাঁচ", "কুটিল বুদ্ধি"), ("বিড়াল তপস্বী", "ভণ্ড সাধু"), ("সোনায় সোহাগা", "উপযুক্ত মিলন"),
    ("মাছের মায়ের পুত্রশোক", "মিথ্যা শোক"), ("অষ্টরম্ভা", "ফাঁকি"), ("কলুর বলদ", "একটানা খাটুনি"), ("নিমক হারাম", "অকৃতজ্ঞ"),
    ("হাটে হাঁড়ি ভাঙা", "গোপন কথা প্রকাশ করে দেওয়া"), ("উলুবনে মুক্তা ছড়ানো", "অপাত্রে দান"), ("শাঁখের করাত", "উভয় সংকট"),
    ("লেফাফা দুরস্ত", "বাইরের ঠাট বজায় রাখা"), ("কেতাদুরস্ত", "পরিপাটি"), ("ঢাক ঢাক গুড় গুড়", "গোপন রাখার চেষ্টা"),
    ("ধরি মাছ না ছুঁই পানি", "কৌশলে কাজ সারা"), ("চিনির বলদ", "ভারবাহী কিন্তু ফলভোগী নয়")]

EK_KOTHAY = [("যা পূর্বে ছিল না", "অভূতপূর্ব"), ("যা বলার যোগ্য নয়", "অকথ্য"), ("যা নিবারণ করা কষ্টকর", "দুর্নিবার"),
    ("যার বংশ পরিচয় জানা নেই", "অজ্ঞাতকুলশীল"), ("যা কষ্টে লাভ করা যায়", "দুর্লভ"), ("যা পূর্বে দেখা যায়নি", "অদৃষ্টপূর্ব"),
    ("যার কোনো উপায় নেই", "নিরুপায়"), ("যা নশ্বর নয়", "অবিনশ্বর"), ("যে নারী বীর সন্তান প্রসব করে", "বীরপ্রসূ"),
    ("ফল পাকলে যে গাছ মরে যায়", "ওষধি"), ("বেঁচে থাকার ইচ্ছা", "জিজীবিষা"), ("জয় করার ইচ্ছা", "জিগীষা"),
    ("যুদ্ধ করার ইচ্ছা", "যুযুৎসা"), ("যা দীপ্তি পাচ্ছে", "দেদীপ্যমান"), ("যার স্ত্রী মারা গেছে", "বিপত্নীক"),
    ("যার কোনো শত্রু জন্মায়নি", "অজাতশত্রু"), ("যে নারী সূর্য দেখে না", "অসূর্যম্পশ্যা"), ("সকলের জন্য প্রযোজ্য", "সর্বজনীন"),
    ("উপকারীর উপকার স্বীকার করে যে", "কৃতজ্ঞ"), ("উপকারীর অপকার করে যে", "কৃতঘ্ন"), ("আকাশে চরে যে", "খেচর"),
    ("জলে চরে যে", "জলচর"), ("মাটি ভেদ করে ওঠে যা", "উদ্ভিদ"), ("অন্যের রচনা চুরি করে নিজের নামে চালানো", "কুম্ভিলকবৃত্তি"),
    ("যা সহজে ভাঙে", "ভঙ্গুর"), ("যা আগে কখনো শোনা যায়নি", "অশ্রুতপূর্ব"), ("যা অতি দীর্ঘ নয়", "নাতিদীর্ঘ"),
    ("ক্ষমার যোগ্য", "ক্ষমার্হ"), ("পান করার যোগ্য", "পেয়"), ("যা চিরস্থায়ী নয়", "ক্ষণস্থায়ী")]

SANDHI = [("বিদ্যালয়", "বিদ্যা + আলয়"), ("হিমালয়", "হিম + আলয়"), ("সূর্যোদয়", "সূর্য + উদয়"), ("মহোৎসব", "মহা + উৎসব"),
    ("নাবিক", "নৌ + ইক"), ("পবন", "পো + অন"), ("নায়ক", "নৈ + অক"), ("গবেষণা", "গো + এষণা"), ("স্বাগত", "সু + আগত"),
    ("প্রত্যেক", "প্রতি + এক"), ("অত্যন্ত", "অতি + অন্ত"), ("ইত্যাদি", "ইতি + আদি"), ("জগন্নাথ", "জগৎ + নাথ"),
    ("উল্লাস", "উৎ + লাস"), ("নিরাশা", "নিঃ + আশা"), ("দুরবস্থা", "দুঃ + অবস্থা"), ("মনোরম", "মনঃ + রম"),
    ("পুরস্কার", "পুরঃ + কার"), ("বৃহস্পতি", "বৃহৎ + পতি"), ("পতঞ্জলি", "পতৎ + অঞ্জলি"), ("গবাক্ষ", "গো + অক্ষ"),
    ("সংগীত", "সম্ + গীত"), ("উচ্ছেদ", "উৎ + ছেদ"), ("দিগন্ত", "দিক্ + অন্ত"), ("বাগীশ", "বাক্ + ঈশ"),
    ("সদ্যোজাত", "সদ্যঃ + জাত"), ("দ্বৈপায়ন", "দ্বীপ + অয়ন"), ("পরীক্ষা", "পরি + ঈক্ষা"), ("মহর্ষি", "মহা + ঋষি"),
    ("একৈক", "এক + এক")]

AUTHORS_BN = [("গীতাঞ্জলি", "রবীন্দ্রনাথ ঠাকুর"), ("গোরা", "রবীন্দ্রনাথ ঠাকুর"), ("চোখের বালি", "রবীন্দ্রনাথ ঠাকুর"),
    ("অগ্নিবীণা", "কাজী নজরুল ইসলাম"), ("বাঁধনহারা", "কাজী নজরুল ইসলাম"), ("মৃত্যুক্ষুধা", "কাজী নজরুল ইসলাম"),
    ("দুর্গেশনন্দিনী", "বঙ্কিমচন্দ্র চট্টোপাধ্যায়"), ("কপালকুণ্ডলা", "বঙ্কিমচন্দ্র চট্টোপাধ্যায়"), ("দেবদাস", "শরৎচন্দ্র চট্টোপাধ্যায়"),
    ("শ্রীকান্ত", "শরৎচন্দ্র চট্টোপাধ্যায়"), ("পথের দাবী", "শরৎচন্দ্র চট্টোপাধ্যায়"), ("মেঘনাদবধ কাব্য", "মাইকেল মধুসূদন দত্ত"),
    ("বুড়ো সালিকের ঘাড়ে রোঁ", "মাইকেল মধুসূদন দত্ত"), ("নকশী কাঁথার মাঠ", "জসীমউদ্দীন"), ("সোজন বাদিয়ার ঘাট", "জসীমউদ্দীন"),
    ("পথের পাঁচালী", "বিভূতিভূষণ বন্দ্যোপাধ্যায়"), ("আরণ্যক", "বিভূতিভূষণ বন্দ্যোপাধ্যায়"), ("বিষাদ-সিন্ধু", "মীর মশাররফ হোসেন"),
    ("বন্দী শিবির থেকে", "শামসুর রাহমান"), ("লালসালু", "সৈয়দ ওয়ালীউল্লাহ"), ("নন্দিত নরকে", "হুমায়ূন আহমেদ"),
    ("হাজার বছর ধরে", "জহির রায়হান"), ("সংশপ্তক", "শহীদুল্লা কায়সার"), ("চিলেকোঠার সেপাই", "আখতারুজ্জামান ইলিয়াস"),
    ("খোয়াবনামা", "আখতারুজ্জামান ইলিয়াস"), ("হাঙর নদী গ্রেনেড", "সেলিনা হোসেন"), ("সুলতানার স্বপ্ন", "বেগম রোকেয়া"),
    ("অবরোধবাসিনী", "বেগম রোকেয়া"), ("ছাড়পত্র", "সুকান্ত ভট্টাচার্য"), ("রূপসী বাংলা", "জীবনানন্দ দাশ"),
    ("বনলতা সেন", "জীবনানন্দ দাশ"), ("পদ্মানদীর মাঝি", "মানিক বন্দ্যোপাধ্যায়"), ("নীলদর্পণ", "দীনবন্ধু মিত্র"),
    ("আলালের ঘরের দুলাল", "প্যারীচাঁদ মিত্র"), ("হুতোম প্যাঁচার নকশা", "কালীপ্রসন্ন সিংহ"), ("কবর", "মুনীর চৌধুরী"),
    ("রক্তাক্ত প্রান্তর", "মুনীর চৌধুরী"), ("জননী", "শওকত ওসমান"), ("ক্রীতদাসের হাসি", "শওকত ওসমান"),
    ("তেইশ নম্বর তৈলচিত্র", "আলাউদ্দিন আল আজাদ"), ("সাম্যবাদী", "কাজী নজরুল ইসলাম"), ("বিদ্রোহী", "কাজী নজরুল ইসলাম"),
    ("শেষের কবিতা", "রবীন্দ্রনাথ ঠাকুর"), ("ঘরে বাইরে", "রবীন্দ্রনাথ ঠাকুর"), ("আনন্দমঠ", "বঙ্কিমচন্দ্র চট্টোপাধ্যায়"),
    ("চাঁদের অমাবস্যা", "সৈয়দ ওয়ালীউল্লাহ"), ("জীবন থেকে নেয়া", "জহির রায়হান"), ("একটি কালো মেয়ের কথা", "তারাশঙ্কর বন্দ্যোপাধ্যায়"),
    ("আমার সোনার বাংলা", "রবীন্দ্রনাথ ঠাকুর"), ("জীবনস্মৃতি", "রবীন্দ্রনাথ ঠাকুর"), ("আত্মচরিত", "ঈশ্বরচন্দ্র বিদ্যাসাগর")]

def bangla():
    D = {"t": "derived", "note": "প্রমিত বানানের তালিকা থেকে ইচ্ছাকৃত ভুল-বিকল্প"}
    for w in CORRECT_BN:
        bad = corruptions(w); R.shuffle(bad)
        if len(bad) >= 3:
            add("bangla", "spelling", 2, "কোন বানানটি শুদ্ধ?", w, bad[:3], f"শুদ্ধ বানান: {w}", D)
        if len(bad) >= 1:
            others = pick(CORRECT_BN, 3, {w})
            add("bangla", "spelling", 2, "কোন বানানটি অশুদ্ধ?", bad[0], others, f"শুদ্ধ রূপ: {w}", D)
    allsyn = {g: s.split() for g, s in SYN_GROUPS}
    for g, words in allsyn.items():
        others = [x for k, v in allsyn.items() if k != g for x in v]
        for w in words:
            add("bangla", "synonym", 2, f"'{g}' শব্দের সমার্থক কোনটি?", w, pick(others, 3, set()), "")
            add("bangla", "synonym", 2, f"'{w}' কোন শব্দের সমার্থক?", g, pick([k for k in allsyn if k != g], 3, set()), "")
    pairs = [p.split("-") for p in ANT_BN]
    rights = [b for _, b in pairs]
    for a, b in pairs:
        add("bangla", "antonym", 2, f"'{a}' শব্দের বিপরীত শব্দ কোনটি?", b, pick(rights, 3, {b, a}), f"{a} ↔ {b}")
    means = [m for _, m in BAGDHARA]
    for p, m in BAGDHARA:
        add("bangla", "idiom", 2, f"'{p}' বাগধারার অর্থ কী?", m, pick(means, 3, {m}), "")
    words = [w for _, w in EK_KOTHAY]
    for p, w in EK_KOTHAY:
        add("bangla", "one_word", 2, f"'{p}' — এক কথায় প্রকাশ কী?", w, pick(words, 3, {w}), "")
    splits = [s for _, s in SANDHI]
    for w, s in SANDHI:
        add("bangla", "sandhi", 3, f"'{w}' শব্দের সন্ধিবিচ্ছেদ কোনটি?", s, pick(splits, 3, {s}), "")
    authors = list(dict.fromkeys(a for _, a in AUTHORS_BN)); works = [w for w, _ in AUTHORS_BN]
    by_author = {}
    for w, a in AUTHORS_BN:
        by_author.setdefault(a, []).append(w)
    for w, a in AUTHORS_BN:
        add("bangla", "literature", 2, f"'{w}' কার রচনা?", a, pick(authors, 3, {a}), "")
        add("bangla", "literature", 2, f"{a}-এর রচনা কোনটি?", w, pick(works, 3, set(by_author[a])), "")

# ================================================================== ENGLISH
SYN_EN = """abandon:desert abundant:plentiful accurate:precise adversary:opponent ample:sufficient benevolent:kind brief:concise
candid:frank cease:stop commence:begin conceal:hide courage:bravery diligent:industrious eminent:distinguished enormous:huge
fragile:delicate frugal:thrifty hostile:unfriendly imminent:impending impartial:unbiased lucid:clear meagre:scanty
obsolete:outdated obstinate:stubborn pragmatic:practical prudent:wise reluctant:unwilling scarce:rare tranquil:calm vague:unclear
wealthy:rich zeal:enthusiasm ardent:passionate audacious:bold cordial:friendly deceit:fraud eloquent:articulate feeble:weak
genuine:authentic hazard:danger jubilant:joyful lethargic:sluggish mandatory:compulsory novice:beginner ominous:threatening
placid:peaceful quarrel:dispute rigorous:strict tedious:boring ubiquitous:omnipresent vindicate:justify wary:cautious""".split()
ANT_EN = """ancient:modern arrogant:humble artificial:natural benevolent:malevolent brave:cowardly cheap:expensive compulsory:optional
conceal:reveal deep:shallow expand:contract frequent:rare generous:stingy guilty:innocent import:export increase:decrease
inferior:superior maximum:minimum optimist:pessimist permanent:temporary presence:absence rigid:flexible scarcity:abundance
sorrow:joy transparent:opaque victory:defeat wisdom:folly ascend:descend acquit:convict encourage:discourage include:exclude
majority:minority accept:reject admire:despise barren:fertile dynamic:static external:internal""".split()
SPELL_EN = """accommodate achievement acquaintance address apparent argument beginning believe business calendar colleague committee
conscience conscious definitely embarrass environment exaggerate existence fluorescent foreign government grammar guarantee harass
immediately independent knowledge liaison library maintenance millennium necessary noticeable occasion occurred occurrence
parliament perseverance possession privilege pronunciation questionnaire receive recommend referred relevant restaurant rhythm
schedule separate successful surprise threshold tomorrow tyranny unnecessary vacuum Wednesday weird withhold lieutenant
bureaucracy entrepreneur mischievous""".split()
VERBS = """go:went:gone take:took:taken write:wrote:written rise:rose:risen bite:bit:bitten fly:flew:flown forbid:forbade:forbidden
swim:swam:swum sing:sang:sung drink:drank:drunk begin:began:begun freeze:froze:frozen steal:stole:stolen tear:tore:torn wear:wore:worn
shake:shook:shaken choose:chose:chosen speak:spoke:spoken break:broke:broken drive:drove:driven ride:rode:ridden strike:struck:struck
slay:slew:slain spring:sprang:sprung swear:swore:sworn see:saw:seen know:knew:known grow:grew:grown seek:sought:sought
teach:taught:taught catch:caught:caught fight:fought:fought lay:laid:laid weep:wept:wept wind:wound:wound cling:clung:clung""".split()
PLURALS = """ox:oxen child:children mouse:mice goose:geese louse:lice tooth:teeth analysis:analyses crisis:crises thesis:theses
phenomenon:phenomena criterion:criteria radius:radii nucleus:nuclei axis:axes oasis:oases basis:bases stratum:strata
alumnus:alumni bacterium:bacteria sheep:sheep deer:deer aircraft:aircraft mother-in-law:mothers-in-law passer-by:passers-by
commander-in-chief:commanders-in-chief""".split()
IDIOMS_EN = [("a piece of cake", "very easy"), ("at sixes and sevens", "in disorder"), ("bad blood", "enmity"),
    ("break the ice", "start a conversation"), ("by leaps and bounds", "very rapidly"), ("call a spade a spade", "speak frankly"),
    ("cry for the moon", "want the impossible"), ("hand in glove", "very intimate"), ("in a nutshell", "briefly"),
    ("once in a blue moon", "very rarely"), ("red-letter day", "a memorable day"), ("to bell the cat", "to face a risk"),
    ("white elephant", "a costly but useless possession"), ("a bolt from the blue", "a sudden shock"),
    ("apple of discord", "cause of quarrel"), ("at a stone's throw", "very near"), ("bird's eye view", "a general view"),
    ("black sheep", "a disgraceful member"), ("by fits and starts", "irregularly"), ("dark horse", "an unexpected winner"),
    ("French leave", "absence without permission"), ("in cold blood", "deliberately"), ("to burn the midnight oil", "to study late at night"),
    ("to make a clean breast of", "to confess"), ("null and void", "invalid"), ("up to the mark", "satisfactory"),
    ("lion's share", "the largest part"), ("maiden speech", "first speech"), ("to turn a deaf ear", "to ignore"),
    ("Achilles' heel", "weak point"), ("ins and outs", "full details")]
AUTHORS_EN = [("Hamlet", "William Shakespeare"), ("Macbeth", "William Shakespeare"), ("The Merchant of Venice", "William Shakespeare"),
    ("Paradise Lost", "John Milton"), ("Pride and Prejudice", "Jane Austen"), ("Oliver Twist", "Charles Dickens"),
    ("David Copperfield", "Charles Dickens"), ("A Tale of Two Cities", "Charles Dickens"), ("The Waste Land", "T. S. Eliot"),
    ("Animal Farm", "George Orwell"), ("Nineteen Eighty-Four", "George Orwell"), ("The Old Man and the Sea", "Ernest Hemingway"),
    ("Frankenstein", "Mary Shelley"), ("Ode to the West Wind", "P. B. Shelley"), ("Ode to a Nightingale", "John Keats"),
    ("I Wandered Lonely as a Cloud", "William Wordsworth"), ("The Rime of the Ancient Mariner", "S. T. Coleridge"),
    ("Gulliver's Travels", "Jonathan Swift"), ("Robinson Crusoe", "Daniel Defoe"), ("Arms and the Man", "G. B. Shaw"),
    ("The Canterbury Tales", "Geoffrey Chaucer"), ("Don Juan", "Lord Byron"), ("Ulysses", "James Joyce"), ("War and Peace", "Leo Tolstoy"),
    ("Things Fall Apart", "Chinua Achebe"), ("Doctor Faustus", "Christopher Marlowe"), ("Wuthering Heights", "Emily Brontë"),
    ("Jane Eyre", "Charlotte Brontë"), ("Tess of the d'Urbervilles", "Thomas Hardy"), ("Sons and Lovers", "D. H. Lawrence"),
    ("The Raven", "Edgar Allan Poe"), ("Leaves of Grass", "Walt Whitman"), ("Waiting for Godot", "Samuel Beckett")]

def en_corrupt(w):
    out = set()
    for i in range(len(w) - 1):
        if w[i] == w[i + 1]:
            out.add(w[:i] + w[i + 1:])
    for i, c in enumerate(w):
        if 0 < i < len(w) - 1 and c in "cmlnstpr" and w[i + 1] != c and w[i - 1] != c:
            out.add(w[:i] + c + c + w[i + 1:])
    out.add(w.replace("ie", "ei")); out.add(w.replace("ei", "ie"))
    for a, b in (("a", "e"), ("e", "a"), ("ance", "ence"), ("ence", "ance"), ("able", "ible"), ("ar", "er")):
        if a in w:
            out.add(w.replace(a, b, 1))
    return [o for o in out if o != w and o.lower() not in {x.lower() for x in SPELL_EN}]

def english():
    pairs = [p.split(":") for p in SYN_EN]; syns = [b for _, b in pairs]
    for a, b in pairs:
        add("english", "synonym", 2, f"Choose the synonym of '{a}':", b, pick(syns, 3, {b}), "")
    pairs = [p.split(":") for p in ANT_EN]; ants = [b for _, b in pairs]
    for a, b in pairs:
        add("english", "antonym", 2, f"Choose the antonym of '{a}':", b, pick(ants, 3, {b}), "")
    for w in SPELL_EN:
        bad = en_corrupt(w); R.shuffle(bad)
        if len(bad) >= 3:
            add("english", "spelling", 2, "Which spelling is correct?", w, bad[:3], "", {"t": "derived"})
    rows = [v.split(":") for v in VERBS]
    for base, past, pp in rows:
        reg = base + ("d" if base.endswith("e") else "ed")
        add("english", "verb", 1, f"Past form of '{base}':", past, [x for x in [pp, reg, base + "s", base + "en"] if x != past][:3], "")
        add("english", "verb", 2, f"Past participle of '{base}':", pp, [x for x in [past, reg, base + "n", base + "ing"] if x != pp][:3], "")
    rows = [v.split(":") for v in PLURALS]
    for s, p in rows:
        add("english", "plural", 2, f"Plural of '{s}':", p, [x for x in [s + "s", s + "es", p + "s", s + "en"] if x != p][:3], "")
    means = [m for _, m in IDIOMS_EN]
    for i, m in IDIOMS_EN:
        add("english", "idiom", 2, f"The phrase '{i}' means:", m, pick(means, 3, {m}), "")
    authors = list(dict.fromkeys(a for _, a in AUTHORS_EN))
    for w, a in AUTHORS_EN:
        add("english", "literature", 2, f"'{w}' was written by:", a, pick(authors, 3, {a}), "")

# ================================================================== GK international
CAPITALS = """আফগানিস্তান:কাবুল আলবেনিয়া:তিরানা আলজেরিয়া:আলজিয়ার্স আর্জেন্টিনা:বুয়েনস_আইরেস আর্মেনিয়া:ইয়েরেভান অস্ট্রেলিয়া:ক্যানবেরা
অস্ট্রিয়া:ভিয়েনা আজারবাইজান:বাকু বাহরাইন:মানামা বেলারুশ:মিনস্ক বেলজিয়াম:ব্রাসেলস ভুটান:থিম্পু ব্রাজিল:ব্রাসিলিয়া
বুলগেরিয়া:সোফিয়া কম্বোডিয়া:নমপেন কানাডা:অটোয়া চিলি:সান্তিয়াগো চীন:বেইজিং কলম্বিয়া:বোগোটা ক্রোয়েশিয়া:জাগরেব
কিউবা:হাভানা চেক_প্রজাতন্ত্র:প্রাগ ডেনমার্ক:কোপেনহেগেন মিশর:কায়রো ইথিওপিয়া:আদ্দিস_আবাবা ফিনল্যান্ড:হেলসিংকি ফ্রান্স:প্যারিস
জর্জিয়া:তিবিলিসি জার্মানি:বার্লিন ঘানা:আক্রা গ্রিস:এথেন্স হাঙ্গেরি:বুদাপেস্ট আইসল্যান্ড:রেইকিয়াভিক ভারত:নয়াদিল্লি ইরান:তেহরান
ইরাক:বাগদাদ আয়ারল্যান্ড:ডাবলিন ইতালি:রোম জাপান:টোকিও জর্ডান:আম্মান কেনিয়া:নাইরোবি কুয়েত:কুয়েত_সিটি কিরগিজস্তান:বিশকেক
লাওস:ভিয়েনতিয়েন লেবানন:বৈরুত লিবিয়া:ত্রিপোলি মালয়েশিয়া:কুয়ালালামপুর মালদ্বীপ:মালে মেক্সিকো:মেক্সিকো_সিটি মঙ্গোলিয়া:উলানবাটোর
মরক্কো:রাবাত মিয়ানমার:নেপিডো নেপাল:কাঠমান্ডু নেদারল্যান্ডস:আমস্টারডাম নিউজিল্যান্ড:ওয়েলিংটন নাইজেরিয়া:আবুজা উত্তর_কোরিয়া:পিয়ংইয়ং
নরওয়ে:অসলো ওমান:মাস্কাট পাকিস্তান:ইসলামাবাদ পেরু:লিমা ফিলিপাইন:ম্যানিলা পোল্যান্ড:ওয়ারশ পর্তুগাল:লিসবন কাতার:দোহা
রোমানিয়া:বুখারেস্ট রাশিয়া:মস্কো সৌদি_আরব:রিয়াদ দক্ষিণ_কোরিয়া:সিউল স্পেন:মাদ্রিদ সুদান:খার্তুম সুইডেন:স্টকহোম সুইজারল্যান্ড:বার্ন
সিরিয়া:দামেস্ক তাজিকিস্তান:দুশানবে থাইল্যান্ড:ব্যাংকক তিউনিসিয়া:তিউনিস তুরস্ক:আঙ্কারা তুর্কমেনিস্তান:আশগাবাত সংযুক্ত_আরব_আমিরাত:আবুধাবি
উগান্ডা:কাম্পালা ইউক্রেন:কিয়েভ যুক্তরাজ্য:লন্ডন যুক্তরাষ্ট্র:ওয়াশিংটন_ডি.সি. উরুগুয়ে:মন্টেভিডিও উজবেকিস্তান:তাসখন্দ ভেনেজুয়েলা:কারাকাস
ভিয়েতনাম:হ্যানয় জিম্বাবুয়ে:হারারে জাম্বিয়া:লুসাকা প্যারাগুয়ে:আসুনসিওন ইকুয়েডর:কিটো সার্বিয়া:বেলগ্রেড স্লোভাকিয়া:ব্রাতিস্লাভা
স্লোভেনিয়া:লুবলিয়ানা লিথুয়ানিয়া:ভিলনিয়াস লাটভিয়া:রিগা এস্তোনিয়া:তালিন সেনেগাল:ডাকার মালি:বামাকো সোমালিয়া:মোগাদিশু
রুয়ান্ডা:কিগালি অ্যাঙ্গোলা:লুয়ান্ডা মোজাম্বিক:মাপুতো মাদাগাস্কার:আন্তানানারিভো ফিজি:সুভা জ্যামাইকা:কিংস্টন""".split()
CURRENCY = """জাপান:ইয়েন চীন:ইউয়ান ভারত:রুপি ভুটান:গুলট্রাম মিয়ানমার:কিয়াত থাইল্যান্ড:বাথ মালয়েশিয়া:রিংগিত ইন্দোনেশিয়া:রুপিয়াহ
ফিলিপাইন:পেসো ভিয়েতনাম:ডং দক্ষিণ_কোরিয়া:ওন যুক্তরাজ্য:পাউন্ড_স্টার্লিং যুক্তরাষ্ট্র:ডলার রাশিয়া:রুবল সৌদি_আরব:রিয়াল
কুয়েত:দিনার তুরস্ক:লিরা দক্ষিণ_আফ্রিকা:র‍্যান্ড সুইজারল্যান্ড:ফ্রাঁ সুইডেন:ক্রোনা পোল্যান্ড:জ্লোটি মালদ্বীপ:রুফিয়া আফগানিস্তান:আফগানি
নাইজেরিয়া:নাইরা কেনিয়া:শিলিং ইউক্রেন:রিভনিয়া কম্বোডিয়া:রিয়েল লাওস:কিপ মঙ্গোলিয়া:তুগরিক জার্মানি:ইউরো বাংলাদেশ:টাকা""".split()
HQ = """জাতিসংঘ:নিউইয়র্ক ইউনেস্কো:প্যারিস বিশ্ব_স্বাস্থ্য_সংস্থা_(WHO):জেনেভা আইএমএফ:ওয়াশিংটন_ডি.সি. বিশ্বব্যাংক:ওয়াশিংটন_ডি.সি.
খাদ্য_ও_কৃষি_সংস্থা_(FAO):রোম আইএলও:জেনেভা ইউনিসেফ:নিউইয়র্ক বিশ্ব_বাণিজ্য_সংস্থা_(WTO):জেনেভা আইএইএ:ভিয়েনা ওপেক:ভিয়েনা
সার্ক:কাঠমান্ডু আসিয়ান:জাকার্তা বিমসটেক:ঢাকা ওআইসি:জেদ্দা ইন্টারপোল:লিওঁ আন্তর্জাতিক_বিচার_আদালত:হেগ ন্যাটো:ব্রাসেলস
ইউরোপীয়_ইউনিয়ন:ব্রাসেলস আফ্রিকান_ইউনিয়ন:আদ্দিস_আবাবা ইউএনএইচসিআর:জেনেভা ইউএনইপি:নাইরোবি বিশ্ব_আবহাওয়া_সংস্থা:জেনেভা
আইটিইউ:জেনেভা ইউপিইউ:বার্ন আইকাও:মন্ট্রিল আইএমও:লন্ডন কমনওয়েলথ:লন্ডন ইসলামী_উন্নয়ন_ব্যাংক:জেদ্দা এশীয়_উন্নয়ন_ব্যাংক:ম্যানিলা
এআইআইবি:বেইজিং নিউ_ডেভেলপমেন্ট_ব্যাংক:সাংহাই রেড_ক্রস_আন্তর্জাতিক_কমিটি:জেনেভা অ্যামনেস্টি_ইন্টারন্যাশনাল:লন্ডন
ট্রান্সপারেন্সি_ইন্টারন্যাশনাল:বার্লিন""".split()

def gk():
    def rows(lst):
        return [(a.replace("_", " "), b.replace("_", " ")) for a, b in (x.split(":") for x in lst)]
    caps = rows(CAPITALS); allc = [c for _, c in caps]; allk = [k for k, _ in caps]
    for k, c in caps:
        add("gk", "capital", 1, f"{k}-এর রাজধানীর নাম কী?", c, pick(allc, 3, {c}), "")
        add("gk", "capital", 2, f"{c} কোন দেশের রাজধানী?", k, pick(allk, 3, {k}), "")
    cur = rows(CURRENCY); allm = [m for _, m in cur]
    for k, m in cur:
        add("gk", "currency", 2, f"{k}-এর মুদ্রার নাম কী?", m, pick(allm, 3, {m}), "")
    hq = rows(HQ); allh = list(dict.fromkeys(h for _, h in hq))
    for o, h in hq:
        add("gk", "hq", 2, f"{o}-এর সদর দপ্তর কোথায়?", h, pick(allh, 3, {h}), "")

# Curated: (question, answer, [3 distractors], explanation)
BD = [
    ("বাংলাদেশে বিভাগের সংখ্যা কয়টি?", "৮টি", ["৭টি", "৬টি", "৯টি"]), ("বাংলাদেশে জেলার সংখ্যা কয়টি?", "৬৪টি", ["৬১টি", "৬৮টি", "৬০টি"]),
    ("বাংলাদেশের জাতীয় ফুল কোনটি?", "শাপলা", ["গোলাপ", "শিউলি", "কদম"]), ("বাংলাদেশের জাতীয় ফল কোনটি?", "কাঁঠাল", ["আম", "লিচু", "কলা"]),
    ("বাংলাদেশের জাতীয় পশু কোনটি?", "রয়েল বেঙ্গল টাইগার", ["হাতি", "হরিণ", "গরু"]), ("বাংলাদেশের জাতীয় পাখি কোনটি?", "দোয়েল", ["ময়না", "কোকিল", "শালিক"]),
    ("বাংলাদেশের জাতীয় বৃক্ষ কোনটি?", "আমগাছ", ["কাঁঠালগাছ", "বটগাছ", "নিমগাছ"]), ("বাংলাদেশের জাতীয় মাছ কোনটি?", "ইলিশ", ["রুই", "পাঙাশ", "চিংড়ি"]),
    ("বাংলাদেশের মহান স্বাধীনতা দিবস কোন তারিখে?", "২৬ মার্চ", ["১৬ ডিসেম্বর", "২১ ফেব্রুয়ারি", "১৭ এপ্রিল"]),
    ("বাংলাদেশের বিজয় দিবস কোন তারিখে?", "১৬ ডিসেম্বর", ["২৬ মার্চ", "১৪ ডিসেম্বর", "৭ মার্চ"]),
    ("ভাষা আন্দোলন কোন সালে সংঘটিত হয়?", "১৯৫২", ["১৯৪৮", "১৯৫৪", "১৯৬৬"]), ("ঐতিহাসিক ছয় দফা ঘোষিত হয় কোন সালে?", "১৯৬৬", ["১৯৬৯", "১৯৬২", "১৯৭০"]),
    ("আগরতলা ষড়যন্ত্র মামলা দায়ের হয় কোন সালে?", "১৯৬৮", ["১৯৬৬", "১৯৬৯", "১৯৬৫"]), ("ঊনসত্তরের গণঅভ্যুত্থান কোন সালে?", "১৯৬৯", ["১৯৬৮", "১৯৭০", "১৯৬৬"]),
    ("মুক্তিযুদ্ধের সময় বাংলাদেশকে কয়টি সেক্টরে ভাগ করা হয়েছিল?", "১১টি", ["৯টি", "১০টি", "১২টি"]),
    ("বীরশ্রেষ্ঠ খেতাবপ্রাপ্ত মুক্তিযোদ্ধা কতজন?", "৭ জন", ["৬ জন", "৮ জন", "৫ জন"]),
    ("মুজিবনগর সরকার শপথ গ্রহণ করে কোন তারিখে?", "১৭ এপ্রিল ১৯৭১", ["১০ এপ্রিল ১৯৭১", "২৬ মার্চ ১৯৭১", "১৬ ডিসেম্বর ১৯৭১"]),
    ("বাংলাদেশের সংবিধান কার্যকর হয় কবে?", "১৬ ডিসেম্বর ১৯৭২", ["৪ নভেম্বর ১৯৭২", "২৬ মার্চ ১৯৭২", "১০ এপ্রিল ১৯৭২"]),
    ("গণপরিষদে বাংলাদেশের সংবিধান গৃহীত হয় কবে?", "৪ নভেম্বর ১৯৭২", ["১৬ ডিসেম্বর ১৯৭২", "১০ জানুয়ারি ১৯৭২", "২১ ফেব্রুয়ারি ১৯৭৩"]),
    ("সুন্দরবন ইউনেস্কো বিশ্ব ঐতিহ্যের তালিকায় স্থান পায় কোন সালে?", "১৯৯৭", ["১৯৮৫", "২০০১", "১৯৯৫"]),
    ("পাহাড়পুর বৌদ্ধবিহার কোন জেলায় অবস্থিত?", "নওগাঁ", ["বগুড়া", "জয়পুরহাট", "রাজশাহী"]),
    ("ষাটগম্বুজ মসজিদ কোন জেলায় অবস্থিত?", "বাগেরহাট", ["খুলনা", "যশোর", "সাতক্ষীরা"]),
    ("মহাস্থানগড় কোন জেলায় অবস্থিত?", "বগুড়া", ["নওগাঁ", "দিনাজপুর", "রংপুর"]), ("লালবাগ কেল্লা কোন শহরে অবস্থিত?", "ঢাকা", ["চট্টগ্রাম", "রাজশাহী", "সোনারগাঁও"]),
    ("বাংলাদেশ জাতিসংঘের সদস্যপদ লাভ করে কোন তারিখে?", "১৭ সেপ্টেম্বর ১৯৭৪", ["১৬ ডিসেম্বর ১৯৭২", "১৮ এপ্রিল ১৯৭২", "২২ ফেব্রুয়ারি ১৯৭৪"]),
    ("বাংলাদেশ জাতিসংঘের কততম সদস্য?", "১৩৬তম", ["১৩৫তম", "১৩৭তম", "১৪০তম"]),
    ("সার্ক প্রতিষ্ঠিত হয় কোন সালে?", "১৯৮৫", ["১৯৮৩", "১৯৮৭", "১৯৮০"]), ("সার্কের প্রথম শীর্ষ সম্মেলন কোথায় অনুষ্ঠিত হয়?", "ঢাকা", ["কাঠমান্ডু", "নয়াদিল্লি", "কলম্বো"]),
    ("কাপ্তাই হ্রদ কোন জেলায় অবস্থিত?", "রাঙামাটি", ["বান্দরবান", "খাগড়াছড়ি", "কক্সবাজার"]),
    ("সেন্ট মার্টিন দ্বীপ কোন জেলায় অবস্থিত?", "কক্সবাজার", ["চট্টগ্রাম", "ভোলা", "পটুয়াখালী"]),
    ("রাতারগুল জলাবন কোন জেলায় অবস্থিত?", "সিলেট", ["মৌলভীবাজার", "সুনামগঞ্জ", "হবিগঞ্জ"]),
    ("পায়রা সমুদ্রবন্দর কোন জেলায় অবস্থিত?", "পটুয়াখালী", ["বরগুনা", "বাগেরহাট", "ভোলা"]),
    ("মোংলা সমুদ্রবন্দর কোন জেলায় অবস্থিত?", "বাগেরহাট", ["খুলনা", "সাতক্ষীরা", "পটুয়াখালী"]),
    ("রূপপুর পারমাণবিক বিদ্যুৎকেন্দ্র কোন জেলায় অবস্থিত?", "পাবনা", ["কুষ্টিয়া", "নাটোর", "সিরাজগঞ্জ"]),
    ("পদ্মা সেতু যানবাহন চলাচলের জন্য উদ্বোধন করা হয় কোন তারিখে?", "২৫ জুন ২০২২", ["২৬ মার্চ ২০২২", "১৬ ডিসেম্বর ২০২১", "২৮ ডিসেম্বর ২০২২"]),
    ("পদ্মা সেতুর দৈর্ঘ্য কত?", "৬.১৫ কিলোমিটার", ["৪.৮ কিলোমিটার", "৫.৬ কিলোমিটার", "৭.২ কিলোমিটার"]),
    ("ঢাকায় মেট্রোরেলের প্রথম অংশ উদ্বোধন হয় কোন তারিখে?", "২৮ ডিসেম্বর ২০২২", ["২৫ জুন ২০২২", "১৬ ডিসেম্বর ২০২২", "২৬ মার্চ ২০২৩"]),
    ("বাংলাদেশের প্রথম যোগাযোগ উপগ্রহ উৎক্ষেপণ করা হয় কোন তারিখে?", "১২ মে ২০১৮", ["১৬ ডিসেম্বর ২০১৭", "২৬ মার্চ ২০১৯", "১ জানুয়ারি ২০১৮"]),
    ("আন্তর্জাতিক মাতৃভাষা দিবস হিসেবে ইউনেস্কো কোন দিনটিকে স্বীকৃতি দেয়?", "২১ ফেব্রুয়ারি", ["২৬ মার্চ", "১৬ ডিসেম্বর", "১৪ এপ্রিল"]),
    ("ইউনেস্কো ২১ ফেব্রুয়ারিকে আন্তর্জাতিক মাতৃভাষা দিবস ঘোষণা করে কোন সালে?", "১৯৯৯", ["২০০০", "১৯৯৭", "২০০১"]),
    ("বাংলাদেশের জাতীয় সংগীতের রচয়িতা কে?", "রবীন্দ্রনাথ ঠাকুর", ["কাজী নজরুল ইসলাম", "জসীমউদ্দীন", "দ্বিজেন্দ্রলাল রায়"]),
    ("বাংলাদেশের রণসংগীত 'চল চল চল'-এর রচয়িতা কে?", "কাজী নজরুল ইসলাম", ["রবীন্দ্রনাথ ঠাকুর", "জসীমউদ্দীন", "সুকান্ত ভট্টাচার্য"]),
    ("জাতীয় স্মৃতিসৌধ কোথায় অবস্থিত?", "সাভার", ["ঢাকা সেনানিবাস", "মুজিবনগর", "গাজীপুর"]),
    ("কেন্দ্রীয় শহীদ মিনারের স্থপতি কে?", "হামিদুর রহমান", ["সৈয়দ মাইনুল হোসেন", "মাজহারুল ইসলাম", "লুই কান"]),
    ("জাতীয় স্মৃতিসৌধের স্থপতি কে?", "সৈয়দ মাইনুল হোসেন", ["হামিদুর রহমান", "লুই কান", "শামীম সিকদার"]),
    ("জাতীয় সংসদ ভবনের স্থপতি কে?", "লুই আই কান", ["সৈয়দ মাইনুল হোসেন", "মাজহারুল ইসলাম", "হামিদুর রহমান"]),
    ("বাংলাদেশের সবচেয়ে বড় হাওর কোনটি?", "হাকালুকি হাওর", ["টাঙ্গুয়ার হাওর", "শনির হাওর", "হাইল হাওর"]),
    ("কক্সবাজার সমুদ্রসৈকতের দৈর্ঘ্য প্রায় কত?", "১২০ কিলোমিটার", ["৮০ কিলোমিটার", "১৫০ কিলোমিটার", "৬০ কিলোমিটার"]),
    ("বাংলাদেশের একমাত্র প্রবাল দ্বীপ কোনটি?", "সেন্ট মার্টিন", ["মহেশখালী", "নিঝুম দ্বীপ", "কুতুবদিয়া"]),
    ("ঐতিহাসিক ৭ মার্চের ভাষণ কোথায় দেওয়া হয়েছিল?", "রেসকোর্স ময়দান", ["পল্টন ময়দান", "বায়তুল মোকাররম", "শহীদ মিনার"]),
    ("কর্ণফুলী নদীর তলদেশে নির্মিত টানেল কোন শহরে?", "চট্টগ্রাম", ["খুলনা", "বরিশাল", "নারায়ণগঞ্জ"]),
    ("বাংলাদেশ কমনওয়েলথের সদস্যপদ লাভ করে কোন সালে?", "১৯৭২", ["১৯৭৪", "১৯৭৩", "১৯৭১"]),
    ("বাংলাদেশ ওআইসির সদস্যপদ লাভ করে কোন সালে?", "১৯৭৪", ["১৯৭২", "১৯৭৬", "১৯৭৩"]),
    ("বাংলাদেশের সংবিধানে মোট কয়টি তফসিল আছে?", "৭টি", ["৫টি", "৬টি", "৪টি"]),
    ("বাংলাদেশের সংবিধানে মোট কয়টি ভাগ আছে?", "১১টি", ["১০টি", "১২টি", "৯টি"]),
    ("সংবিধানের কোন অনুচ্ছেদে সরকারি কর্ম কমিশন প্রতিষ্ঠার কথা বলা হয়েছে?", "১৩৭", ["১৩৬", "১৩৮", "১৪০"]),
    ("বাংলাদেশের সর্বোচ্চ আদালতের নাম কী?", "সুপ্রিম কোর্ট", ["হাইকোর্ট", "জেলা জজ আদালত", "প্রশাসনিক ট্রাইব্যুনাল"]),
    ("বাংলাদেশ সুপ্রিম কোর্টের বিভাগ কয়টি?", "২টি", ["৩টি", "১টি", "৪টি"]),
    ("আহসান মঞ্জিল কোন নদীর তীরে অবস্থিত?", "বুড়িগঙ্গা", ["শীতলক্ষ্যা", "তুরাগ", "বালু"]),
    ("সদরঘাট কোন নদীর তীরে অবস্থিত?", "বুড়িগঙ্গা", ["তুরাগ", "শীতলক্ষ্যা", "মেঘনা"]),
    ("বাংলাদেশের স্বাধীনতার ঘোষণাপত্র কোথা থেকে জারি করা হয়?", "মুজিবনগর", ["ঢাকা", "চট্টগ্রাম", "আগরতলা"]),
    ("বাংলাদেশে পাট গবেষণা ইনস্টিটিউট কোথায় অবস্থিত?", "ঢাকা", ["ময়মনসিংহ", "ফরিদপুর", "রংপুর"]),
    ("বাংলাদেশ কৃষি বিশ্ববিদ্যালয় কোথায় অবস্থিত?", "ময়মনসিংহ", ["গাজীপুর", "দিনাজপুর", "রাজশাহী"]),
    ("বাংলাদেশের মুদ্রার নাম কী?", "টাকা", ["রুপি", "রুপিয়াহ", "দিনার"]),
    ("বাংলাদেশের প্রধান সমুদ্রবন্দর কোনটি?", "চট্টগ্রাম", ["মোংলা", "পায়রা", "মাতারবাড়ী"]),
]
SCI = [
    ("পানির রাসায়নিক সংকেত কী?", "H₂O", ["CO₂", "H₂O₂", "NaCl"]), ("খাদ্য লবণের রাসায়নিক নাম কী?", "সোডিয়াম ক্লোরাইড", ["পটাশিয়াম ক্লোরাইড", "সোডিয়াম কার্বনেট", "ক্যালসিয়াম ক্লোরাইড"]),
    ("সোনার রাসায়নিক সংকেত কী?", "Au", ["Ag", "Gd", "Go"]), ("রুপার রাসায়নিক সংকেত কী?", "Ag", ["Au", "Si", "Rp"]),
    ("লোহার রাসায়নিক সংকেত কী?", "Fe", ["Ir", "Ln", "F"]), ("সোডিয়ামের রাসায়নিক সংকেত কী?", "Na", ["So", "Sd", "N"]),
    ("পটাশিয়ামের রাসায়নিক সংকেত কী?", "K", ["P", "Po", "Pt"]), ("পারদের রাসায়নিক সংকেত কী?", "Hg", ["Pb", "Me", "Pr"]),
    ("সিসার রাসায়নিক সংকেত কী?", "Pb", ["Si", "Sn", "Hg"]), ("টিনের রাসায়নিক সংকেত কী?", "Sn", ["Ti", "Tn", "Sb"]),
    ("ভিটামিন-সি-এর অভাবে কোন রোগ হয়?", "স্কার্ভি", ["রিকেটস", "রাতকানা", "বেরিবেরি"]), ("ভিটামিন-ডি-এর অভাবে শিশুদের কোন রোগ হয়?", "রিকেটস", ["স্কার্ভি", "বেরিবেরি", "পেলাগ্রা"]),
    ("ভিটামিন-এ-এর অভাবে কোন রোগ হয়?", "রাতকানা", ["স্কার্ভি", "রিকেটস", "গলগণ্ড"]), ("ভিটামিন বি১ (থায়ামিন)-এর অভাবে কোন রোগ হয়?", "বেরিবেরি", ["স্কার্ভি", "রাতকানা", "রিকেটস"]),
    ("আয়োডিনের অভাবে কোন রোগ হয়?", "গলগণ্ড", ["রিকেটস", "রক্তশূন্যতা", "রাতকানা"]), ("লৌহের অভাবে কোন রোগ হয়?", "রক্তশূন্যতা", ["গলগণ্ড", "স্কার্ভি", "রিকেটস"]),
    ("রক্ত জমাট বাঁধতে সাহায্য করে কোন ভিটামিন?", "ভিটামিন কে", ["ভিটামিন এ", "ভিটামিন সি", "ভিটামিন ডি"]),
    ("মানবদেহের সবচেয়ে বড় গ্রন্থি কোনটি?", "যকৃৎ", ["অগ্ন্যাশয়", "থাইরয়েড", "পিটুইটারি"]), ("মানবদেহের সবচেয়ে বড় অঙ্গ কোনটি?", "ত্বক", ["যকৃৎ", "ফুসফুস", "মস্তিষ্ক"]),
    ("প্রাপ্তবয়স্ক মানুষের দাঁতের সংখ্যা কয়টি?", "৩২টি", ["২৮টি", "৩০টি", "৩৬টি"]), ("প্রাপ্তবয়স্ক মানুষের হাড়ের সংখ্যা কয়টি?", "২০৬টি", ["২০৮টি", "২১২টি", "১৯৮টি"]),
    ("রক্তের লোহিত কণিকার রং লাল হয় কোন পদার্থের কারণে?", "হিমোগ্লোবিন", ["মেলানিন", "ক্লোরোফিল", "ইনসুলিন"]),
    ("ইনসুলিন নিঃসৃত হয় কোন গ্রন্থি থেকে?", "অগ্ন্যাশয়", ["যকৃৎ", "থাইরয়েড", "অ্যাড্রিনাল"]), ("সর্বজনীন রক্তদাতা কোন গ্রুপ?", "ও নেগেটিভ", ["এবি পজিটিভ", "এ পজিটিভ", "বি নেগেটিভ"]),
    ("সর্বজনীন রক্তগ্রহীতা কোন গ্রুপ?", "এবি পজিটিভ", ["ও নেগেটিভ", "এ নেগেটিভ", "বি পজিটিভ"]), ("ম্যালেরিয়া রোগের বাহক কোনটি?", "অ্যানোফিলিস মশা", ["এডিস মশা", "কিউলেক্স মশা", "মাছি"]),
    ("জলাতঙ্ক রোগের টিকা আবিষ্কার করেন কে?", "লুই পাস্তুর", ["রবার্ট কখ", "এডওয়ার্ড জেনার", "আলেকজান্ডার ফ্লেমিং"]),
    ("পেনিসিলিন আবিষ্কার করেন কে?", "আলেকজান্ডার ফ্লেমিং", ["লুই পাস্তুর", "রবার্ট কখ", "জোনাস সাল্ক"]), ("বসন্তের টিকা আবিষ্কার করেন কে?", "এডওয়ার্ড জেনার", ["লুই পাস্তুর", "রবার্ট কখ", "জোনাস সাল্ক"]),
    ("যক্ষ্মার জীবাণু আবিষ্কার করেন কে?", "রবার্ট কখ", ["লুই পাস্তুর", "এডওয়ার্ড জেনার", "ফ্লেমিং"]), ("বলের এসআই একক কী?", "নিউটন", ["জুল", "ওয়াট", "প্যাসকেল"]),
    ("কাজের এসআই একক কী?", "জুল", ["নিউটন", "ওয়াট", "কেলভিন"]), ("ক্ষমতার এসআই একক কী?", "ওয়াট", ["জুল", "ভোল্ট", "অ্যাম্পিয়ার"]),
    ("চাপের এসআই একক কী?", "প্যাসকেল", ["নিউটন", "বার", "জুল"]), ("তাপমাত্রার এসআই একক কী?", "কেলভিন", ["সেলসিয়াস", "ফারেনহাইট", "জুল"]),
    ("বিদ্যুৎ প্রবাহের এসআই একক কী?", "অ্যাম্পিয়ার", ["ভোল্ট", "ওহম", "ওয়াট"]), ("রোধের এসআই একক কী?", "ওহম", ["অ্যাম্পিয়ার", "ভোল্ট", "কুলম্ব"]),
    ("শব্দের চেয়ে দ্রুতগামী বস্তুর গতিকে কী বলে?", "সুপারসনিক", ["ইনফ্রাসনিক", "আল্ট্রাসনিক", "সাবসনিক"]),
    ("বায়ুমণ্ডলে সবচেয়ে বেশি পরিমাণে থাকে কোন গ্যাস?", "নাইট্রোজেন", ["অক্সিজেন", "কার্বন ডাই-অক্সাইড", "আর্গন"]),
    ("সৌরজগতের বৃহত্তম গ্রহ কোনটি?", "বৃহস্পতি", ["শনি", "নেপচুন", "পৃথিবী"]), ("সূর্যের সবচেয়ে নিকটতম গ্রহ কোনটি?", "বুধ", ["শুক্র", "মঙ্গল", "পৃথিবী"]),
    ("'লাল গ্রহ' নামে পরিচিত কোন গ্রহ?", "মঙ্গল", ["বৃহস্পতি", "শুক্র", "শনি"]), ("আলোর গতি প্রতি সেকেন্ডে প্রায় কত?", "৩ লক্ষ কিলোমিটার", ["৩ হাজার কিলোমিটার", "৩০ লক্ষ কিলোমিটার", "৩৩০ মিটার"]),
    ("বিশুদ্ধ পানির pH মান কত?", "৭", ["১", "১৪", "৫"]), ("প্রাকৃতিক গ্যাসের প্রধান উপাদান কী?", "মিথেন", ["ইথেন", "প্রোপেন", "বিউটেন"]),
    ("সালোকসংশ্লেষণে উদ্ভিদ কোন গ্যাস ত্যাগ করে?", "অক্সিজেন", ["কার্বন ডাই-অক্সাইড", "নাইট্রোজেন", "হাইড্রোজেন"]),
    ("হৃৎপিণ্ডে প্রকোষ্ঠ কয়টি?", "৪টি", ["৩টি", "২টি", "৫টি"]), ("স্বাভাবিক মানুষের দেহের তাপমাত্রা কত?", "৯৮.৪° ফারেনহাইট", ["১০০° ফারেনহাইট", "৯৬° ফারেনহাইট", "৯৯.৯° ফারেনহাইট"]),
    ("ডেঙ্গু রোগের বাহক কোনটি?", "এডিস মশা", ["অ্যানোফিলিস মশা", "মাছি", "তেলাপোকা"]), ("কোন রক্তকণিকা রোগ প্রতিরোধে ভূমিকা রাখে?", "শ্বেত রক্তকণিকা", ["লোহিত রক্তকণিকা", "অণুচক্রিকা", "প্লাজমা"]),
    ("কোন যন্ত্র দিয়ে ভূমিকম্পের তীব্রতা মাপা হয়?", "সিসমোগ্রাফ", ["ব্যারোমিটার", "হাইগ্রোমিটার", "অ্যানিমোমিটার"]),
    ("বায়ুর চাপ মাপার যন্ত্র কোনটি?", "ব্যারোমিটার", ["থার্মোমিটার", "হাইগ্রোমিটার", "ওডোমিটার"]),
]
ICT = [
    ("কম্পিউটারের মস্তিষ্ক বলা হয় কোনটিকে?", "সিপিইউ", ["র‍্যাম", "হার্ডডিস্ক", "মনিটর"]), ("১ বাইট সমান কত বিট?", "৮ বিট", ["৪ বিট", "১৬ বিট", "১০ বিট"]),
    ("১ কিলোবাইট সমান কত বাইট?", "১০২৪ বাইট", ["১০০০ বাইট", "৫১২ বাইট", "২০৪৮ বাইট"]), ("বাইনারি সংখ্যা পদ্ধতির ভিত্তি কত?", "২", ["৮", "১০", "১৬"]),
    ("হেক্সাডেসিমেল সংখ্যা পদ্ধতির ভিত্তি কত?", "১৬", ["৮", "২", "১০"]), ("অক্টাল সংখ্যা পদ্ধতির ভিত্তি কত?", "৮", ["২", "১০", "১৬"]),
    ("কোনটি অস্থায়ী মেমোরি?", "র‍্যাম", ["রম", "হার্ডডিস্ক", "এসএসডি"]), ("কোনটি ইনপুট ডিভাইস?", "কি-বোর্ড", ["মনিটর", "প্রিন্টার", "স্পিকার"]),
    ("কোনটি আউটপুট ডিভাইস?", "প্রিন্টার", ["মাউস", "স্ক্যানার", "কি-বোর্ড"]), ("ই-মেইল পাঠাতে ব্যবহৃত প্রোটোকল কোনটি?", "SMTP", ["POP3", "FTP", "HTTP"]),
    ("ওয়েব পেজ তৈরিতে ব্যবহৃত মার্কআপ ভাষা কোনটি?", "HTML", ["SQL", "C", "Python"]), ("WWW-এর পূর্ণরূপ কী?", "World Wide Web", ["World Web Wide", "Wide World Web", "Web World Wide"]),
    ("URL-এর পূর্ণরূপ কী?", "Uniform Resource Locator", ["Universal Resource Link", "Uniform Record Locator", "Unified Resource Line"]),
    ("CPU-এর পূর্ণরূপ কী?", "Central Processing Unit", ["Central Program Unit", "Computer Processing Unit", "Control Processing Unit"]),
    ("RAM-এর পূর্ণরূপ কী?", "Random Access Memory", ["Read Access Memory", "Rapid Access Memory", "Run Access Memory"]),
    ("ROM-এর পূর্ণরূপ কী?", "Read Only Memory", ["Random Only Memory", "Read Open Memory", "Run Only Memory"]),
    ("কম্পিউটারের জনক বলা হয় কাকে?", "চার্লস ব্যাবেজ", ["অ্যালান টুরিং", "বিল গেটস", "জন নিউম্যান"]), ("প্রথম কম্পিউটার প্রোগ্রামার হিসেবে কাকে ধরা হয়?", "অ্যাডা লাভলেস", ["চার্লস ব্যাবেজ", "গ্রেস হপার", "অ্যালান টুরিং"]),
    ("কোনটি অপারেটিং সিস্টেম?", "লিনাক্স", ["এমএস ওয়ার্ড", "ফটোশপ", "ক্রোম"]), ("কোনটি ওয়েব ব্রাউজার?", "ফায়ারফক্স", ["উইন্ডোজ", "এক্সেল", "লিনাক্স"]),
    ("ডেটাবেজ থেকে তথ্য খুঁজতে ব্যবহৃত ভাষা কোনটি?", "SQL", ["HTML", "CSS", "XML"]), ("কম্পিউটার ভাইরাস আসলে কী?", "একটি ক্ষতিকর প্রোগ্রাম", ["একটি জীবাণু", "একটি হার্ডওয়্যার", "একটি কেবল"]),
    ("ব্লুটুথ কোন ধরনের নেটওয়ার্ক?", "PAN", ["WAN", "MAN", "LAN"]), ("ইন্টারনেটে প্রতিটি ডিভাইস শনাক্তে ব্যবহৃত ঠিকানা কোনটি?", "আইপি অ্যাড্রেস", ["ম্যাক্রো", "ইউআরএল", "ডোমেইন"]),
    ("কোনটি স্প্রেডশিট প্রোগ্রাম?", "এক্সেল", ["ওয়ার্ড", "পাওয়ারপয়েন্ট", "পেইন্ট"]), ("এক বাইনারি অঙ্ককে কী বলে?", "বিট", ["বাইট", "নিবল", "ওয়ার্ড"]),
]

def curated(cat, rows, sub):
    for q, a, ds in rows:
        add(cat, sub, 2, q, a, ds, "")

# ================================================================== main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "..", "data", "questions", "questions.json"))
    a = ap.parse_args()
    past_papers(); law(); math_q(); mental(); bangla(); english(); gk()
    curated("bd", BD, "bangladesh"); curated("science", SCI, "science"); curated("ict", ICT, "ict")
    for it in ITEMS:
        assert len(it["o"]) == 4 and 0 <= it["a"] < 4 and len(set(it["o"])) == 4, it
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump({"version": 2, "count": len(ITEMS), "items": ITEMS}, f, ensure_ascii=False, separators=(",", ":"))
    by = {}
    for it in ITEMS:
        by[it["cat"]] = by.get(it["cat"], 0) + 1
    src = {}
    for it in ITEMS:
        src[it["s"]["t"]] = src.get(it["s"]["t"], 0) + 1
    print("total", len(ITEMS)); print("by category", by); print("by source", src)

if __name__ == "__main__":
    main()
