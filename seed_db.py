import json
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# Initialize connection
cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

with open('seed_data.json', 'r') as file:
    data = json.load(file)

# We use a batch to write multiple documents atomically
batch = db.batch()

# 1. Populate Inventory
for item in data['inventory']:
    doc_ref = db.collection('inventory').document()
    item['id'] = doc_ref.id 
    batch.set(doc_ref, item)

# 2. Populate Shop Settings
settings_ref = db.collection('shop_settings').document('config')
batch.set(settings_ref, data['shop_settings'])

# Commit the batch write
batch.commit()
print("Database successfully populated with Kiosk seed data.")