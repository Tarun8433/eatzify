#!/usr/bin/env python3
"""Apply docs/03 §4 `group:` tags to docs/templates/foods-seed.csv (D-235).

The vocabulary is the spec's own: cereal | pulse | dairy | veg | fruit | nut_seed | meat | fish |
egg | fat_oil | sugar | beverage | prepared. One tag normally; two where a dish honestly carries
two components (idli = cereal+pulse, palak paneer = veg+dairy). `prepared` is deliberately the
group that satisfies NOTHING in a composition rule — street snacks must not structure a main meal.

DRAFT PENDING DIETITIAN REVIEW — classification is data entry against a spec'd vocabulary, but the
judgement calls (potato as veg, butter as fat_oil, sweets as sugar) need a professional eye.

Usage: python3 api/scripts/tag-food-groups.py            # rewrites the CSV in place
       python3 api/scripts/tag-food-groups.py --sql      # also prints UPDATEs for a live DB
"""

import csv
import sys

CSV = 'docs/templates/foods-seed.csv'

# fmt: off
GROUPS: dict[str, list[str]] = {
    # — cereals and breads —
    **{n: ['cereal'] for n in [
        'Roti (whole wheat)', 'Bajra roti', 'Jowar roti', 'Ragi roti', 'Missi roti', 'Makki roti',
        'Tandoori roti', 'Naan (plain)', 'Butter naan', 'Kulcha', 'Paratha (plain)', 'Methi thepla',
        'Khakhra', 'Poori', 'Bhatura', 'Rice (cooked white)', 'Rice (cooked brown)',
        'Basmati rice (cooked)', 'Parboiled rice (cooked)', 'Poha (cooked)', 'Upma',
        'Daliya (cooked)', 'Oats porridge (cooked in water)', 'Oats (raw rolled)', 'Quinoa (cooked)',
        'Muesli (fruit and nut)', 'Cornflakes (plain)', 'White bread', 'Brown bread',
        'Multigrain bread', 'Pasta (cooked)', 'Sabudana khichdi', 'Puffed rice (murmura)',
        'Suji / rava (raw)', 'Wheat flour (atta)', 'Maida (refined flour)', 'Popcorn (plain)',
    ]},
    'Aloo paratha': ['cereal', 'veg'], 'Gobhi paratha': ['cereal', 'veg'],
    'Paneer paratha': ['cereal', 'dairy'],
    # fermented rice-and-dal mains carry both components
    'Idli': ['cereal', 'pulse'], 'Plain dosa': ['cereal', 'pulse'],
    'Masala dosa': ['cereal', 'pulse'], 'Uttapam': ['cereal', 'pulse'],
    'Appam': ['cereal'], 'Dhokla': ['cereal', 'pulse'],
    'Khichdi (moong dal)': ['cereal', 'pulse'],
    'Veg pulao': ['cereal', 'veg'], 'Veg biryani': ['cereal', 'veg'],
    'Chicken biryani': ['cereal', 'meat'], 'Mutton biryani': ['cereal', 'meat'],
    'Veg fried rice': ['cereal', 'veg'],
    # — pulses —
    **{n: ['pulse'] for n in [
        'Besan (gram flour)', 'Sattu (roasted gram)', 'Dal (arhar cooked)',
        'Moong dal (dhuli, cooked)', 'Moong sabut (cooked)', 'Sprouted moong',
        'Masoor dal (cooked)', 'Chana dal (cooked)', 'Urad dal (cooked)', 'Dal makhani',
        'Rajma (cooked)', 'Chole (kabuli chana, cooked)', 'Kala chana (cooked)', 'Lobia (cooked)',
        'Moth bean (cooked)', 'Soybean (cooked)', 'Soya chunks (dry)', 'Tofu',
        'Dried peas (cooked)', 'Rajma curry', 'Chana masala', 'Dal tadka', 'Papad (roasted)',
    ]},
    'Sambar': ['pulse', 'veg'], 'Kadhi': ['pulse', 'dairy'],
    # — dairy —
    **{n: ['dairy'] for n in [
        'Milk (full fat, cow)', 'Milk (toned)', 'Milk (double toned)', 'Skimmed milk',
        'Buffalo milk', 'Curd (full fat)', 'Curd (low fat)', 'Greek yogurt (plain)', 'Paneer',
        'Paneer (low fat)', 'Khoya (mawa)', 'Processed cheese', 'Buttermilk (chaas)', 'Sweet lassi',
        'Salted lassi', 'Condensed milk (sweetened)', 'Milk powder (whole)', 'Shrikhand',
        'Boondi raita', 'Whey protein powder',
    ]},
    'Cucumber raita': ['dairy', 'veg'],
    'Palak paneer': ['veg', 'dairy'], 'Matar paneer': ['veg', 'dairy'],
    # — vegetables (potato and other starchy roots stay veg; flag for review) —
    **{n: ['veg'] for n in [
        'Potato (boiled)', 'Aloo sabzi', 'Onion (raw)', 'Tomato (raw)', 'Brinjal (cooked)',
        'Lauki (cooked)', 'Tinda (cooked)', 'Parwal (cooked)', 'Karela (cooked)', 'Bhindi (cooked)',
        'Cauliflower (cooked)', 'Cabbage (cooked)', 'Capsicum (cooked)', 'Carrot (raw)',
        'Beetroot (boiled)', 'Radish (mooli, raw)', 'Cucumber', 'Spinach (palak, cooked)',
        'Methi leaves (cooked)', 'Sarson ka saag', 'Bathua (cooked)', 'Amaranth leaves (cooked)',
        'Drumstick (cooked)', 'Pumpkin (kaddu, cooked)', 'Ash gourd (petha)',
        'Cluster beans (gawar)', 'French beans (cooked)', 'Sweet potato (boiled)',
        'Arbi (colocasia, cooked)', 'Yam (jimikand, cooked)', 'Mushroom (cooked)',
        'Broccoli (cooked)', 'Zucchini (cooked)', 'Sweet corn (boiled)', 'Turnip (shalgam, cooked)',
        'Ivy gourd (kundru)', 'Raw jackfruit (cooked)', 'Spring onion', 'Mixed veg sabzi',
        'Baingan bharta', 'Aloo gobhi', 'Bhindi masala', 'Green peas (cooked)',
        'Veg kofta curry', 'Raw banana (plantain)',
    ]},
    # — fruit —
    **{n: ['fruit'] for n in [
        'Apple', 'Banana', 'Mango', 'Papaya', 'Guava', 'Orange', 'Sweet lime (mosambi)', 'Grapes',
        'Pomegranate', 'Watermelon', 'Muskmelon', 'Pear', 'Pineapple', 'Chikoo (sapota)',
        'Custard apple', 'Litchi', 'Jamun', 'Ber (Indian jujube)', 'Strawberry', 'Kiwi',
        'Dates (dry)', 'Raisins', 'Dry figs (anjeer)', 'Amla', 'Avocado', 'Plum', 'Peach',
        'Dry apricot', 'Cherries',
    ]},
    # — egg —
    **{n: ['egg'] for n in [
        'Egg (whole, boiled)', 'Egg white (boiled)', 'Egg yolk', 'Omelette (plain)', 'Egg bhurji',
        'Egg curry',
    ]},
    # — meat —
    **{n: ['meat'] for n in [
        'Chicken breast (cooked, skinless)', 'Chicken thigh (cooked)', 'Chicken curry',
        'Tandoori chicken', 'Chicken tikka', 'Chicken keema', 'Chicken soup', 'Chicken sausage',
        'Mutton curry', 'Mutton keema', 'Goat liver (cooked)',
    ]},
    # — fish and shellfish —
    **{n: ['fish'] for n in [
        'Rohu fish (cooked)', 'Pomfret (cooked)', 'Surmai / kingfish (cooked)', 'Hilsa (cooked)',
        'Sardine (cooked)', 'Tuna (canned in water)', 'Prawns (cooked)', 'Crab (cooked)',
        'Fish curry', 'Fish fry',
    ]},
    # — nuts and seeds —
    **{n: ['nut_seed'] for n in [
        'Almond', 'Cashew', 'Walnut', 'Pistachio', 'Peanut (roasted)', 'Peanut butter',
        'Sunflower seeds', 'Pumpkin seeds', 'Flax seeds', 'Chia seeds', 'Sesame seeds (til)',
        'Makhana (fox nut)', 'Fresh coconut', 'Dry coconut (copra)',
    ]},
    # — fats and oils (dairy fats live here: composition-wise butter is a fat, not a dairy serve) —
    **{n: ['fat_oil'] for n in [
        'Butter', 'Ghee', 'Fresh cream', 'Malai', 'Coconut oil', 'Mustard oil', 'Sunflower oil',
        'Groundnut oil', 'Olive oil', 'Rice bran oil', 'Vanaspati', 'Mayonnaise',
    ]},
    # — sweets and sugars —
    **{n: ['sugar'] for n in [
        'Marie biscuit', 'Glucose biscuit', 'Cream biscuit', 'Gulab jamun', 'Rasgulla', 'Jalebi',
        'Besan laddu', 'Motichoor laddu', 'Kaju barfi', 'Gajar halwa', 'Suji halwa', 'Kheer (rice)',
        'Gajak', 'Peanut chikki', 'Vanilla ice cream', 'Milk chocolate', 'Tomato ketchup',
        'Mixed fruit jam', 'Honey', 'Sugar', 'Jaggery (gud)', 'Tamarind chutney',
    ]},
    # — beverages —
    **{n: ['beverage'] for n in [
        'Tea with milk and sugar', 'Tea with milk, no sugar', 'Black tea (no sugar)', 'Green tea',
        'Coffee with milk and sugar', 'Black coffee (no sugar)', 'Cola soft drink',
        'Packaged mango juice', 'Sweet lime soda', 'Coconut water', 'Sugarcane juice',
        'Fresh lime water (no sugar)',
    ]},
    # — prepared / street food: composed dishes that must NOT structure a main meal —
    **{n: ['prepared'] for n in [
        'Instant noodles (cooked)', 'Samosa', 'Pakora (mixed)', 'Kachori', 'Vada pav', 'Pav bhaji',
        'Chole bhature', 'Bhel puri', 'Pani puri', 'Aloo tikki', 'Veg momos', 'Veg spring roll',
        'Chicken momos', 'Namkeen mixture', 'Sev', 'Potato chips', 'French fries', 'Mango pickle',
        'Mint chutney', 'Coconut chutney',
    ]},
}
# fmt: on

VOCAB = {'cereal', 'pulse', 'dairy', 'veg', 'fruit', 'nut_seed', 'meat', 'fish', 'egg', 'fat_oil',
         'sugar', 'beverage', 'prepared'}


def main() -> None:
    for name, groups in GROUPS.items():
        bad = set(groups) - VOCAB
        if bad:
            sys.exit(f'{name}: not in docs/03 vocabulary: {bad}')

    with open(CSV, newline='') as f:
        rows = list(csv.DictReader(f))
        fields = list(rows[0].keys())

    missing = [r['name'] for r in rows if r['name'] not in GROUPS]
    if missing:
        sys.exit(f'unmapped foods ({len(missing)}): {missing[:10]}')

    sql: list[str] = []
    for r in rows:
        tags = [t for t in r['tags'].split('|') if t and not t.startswith('group:')]
        group_tags = [f'group:{g}' for g in GROUPS[r['name']]]
        r['tags'] = '|'.join(group_tags + tags)
        arr = ','.join(f'"{t}"' for t in group_tags)
        safe = r['name'].replace("'", "''")
        sql.append(
            "UPDATE food SET tags = ARRAY(SELECT DISTINCT unnest(tags || '{" + arr + "}'))"
            f" WHERE name = '{safe}';"
        )

    with open(CSV, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f'tagged {len(rows)} rows in {CSV}')
    if '--sql' in sys.argv:
        print('\n'.join(sql))


if __name__ == '__main__':
    main()
