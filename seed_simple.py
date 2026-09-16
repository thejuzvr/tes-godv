import psycopg2, uuid

conn = psycopg2.connect(host='62.122.99.214', port=54321, dbname='tes-godv', user='tes-godv', password='Mo90p4mo!!!')
cur = conn.cursor()
total = 0

data = [
    ('spot_bandits', 'Bandits spotted near the road. Time for action.'),
    ('travel_shortcut', 'Found a shortcut through the hills. A risky but faster path.'),
    ('enter_city', 'City gates opened wide. Civilization at last.'),
    ('bad_weather', 'Rain poured down. Clothes soaked in seconds.'),
    ('find_abandoned_cart', 'Abandoned cart on roadside. Goods scattered.'),
    ('notice_tracks', 'Fresh tracks on the ground. Someone passed recently.'),
    ('hear_river', 'Sound of river grew louder ahead.'),
    ('find_tracks', 'Chain of tracks headed north.'),
    ('hear_birds', 'Birds sang in the forest canopy.'),
    ('smell_flowers', 'Sweet scent of flowers filled the air.'),
    ('learn_rumors', 'Tavern talk hinted at treasure east of here.'),
    ('hear_song', 'Melody drifted from a distant tavern.'),
    ('shelter_from_storm', 'Storm approached. Found shelter under rock ledge.'),
    ('discover_treasure', 'Chest gleamed under ancient roots.'),
    ('remember_defeat', 'Memory of recent defeat lingers.'),
    ('feel_confident', 'Confidence overflowed after recent victory.'),
    ('avoid_danger', 'Intuition warned of danger ahead. Chose safer path.'),
    ('search_danger', 'Danger did not frighten. Moved toward the noise.'),
    ('collect_herbs', 'Healing herbs grew by the stream.'),
    ('hero_defeat', 'Defeated but spirit remains unbroken.'),
]

for etype, txt in data:
    tid = str(uuid.uuid4())
    cur.execute(
        "INSERT INTO narrative_templates (id, template_type, text_template, is_active, source, inserted_at) VALUES (%s,%s,%s,true,'system',NOW())",
        (tid, etype, txt)
    )
    total += 1

conn.commit()
conn.close()
