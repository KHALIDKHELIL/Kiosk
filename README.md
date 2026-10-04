# kiosk

A robust, production-ready Point-of-Sale (POS) and Inventory tracker built specifically for the Ethiopian retail market. Developed with Flutter and Firebase, this system enforces strict profit-margin rules, gamifies the worker experience, and provides deep financial analytics for shop owners.

## ✨ Key Features

### 👨‍💼 Executive Admin Dashboard
* **True Calendar Analytics:** Accurately calculates Average Daily Net Profit, Gross Margins, and Projected Yearly Net based on actual days active, minus fixed break-even overhead (1,000 ETB).
* **Unified CSV Export:** Instantly generate and export a combined Sales & Expenses ledger directly to the native Android Share Sheet for easy forwarding to Telegram, WhatsApp, or Email.
* **Smart Expense Auditing:** View all logged worker expenses (Food, Transport, Supplies) in a dedicated UI.
* **30-Day Cancellation:** Admins can securely cancel and refund stock for any transaction made within the last 30 days.
* **Loss Prevention Safety Lock:** Admins can override minimum price limits but are hard-capped at a 50% discount to prevent catastrophic typos.

### 🏪 Worker Gamification & POS
* **Live Team Feed & Leaderboards:** Workers see a real-time feed of team deals and compete on a daily profit leaderboard to drive sales.
* **Dynamic Motivation:** UI banners adapt in real-time based on the worker's distance from their daily target.
* **Smart Searchable Inventory:** Fast Autocomplete dropdown allows workers to instantly search hundreds of products by typing.
* **Strict Profit Enforcement:** Workers cannot sell items below the calculated wholesale base cost without Admin override.
* **15-Minute Void Window:** Workers can instantly void accidental transactions within 15 minutes to automatically restore inventory stock.
* **Expense Logger with Buffer Logic:** Non-essential business expenses are blocked unless the shop's daily profit has cleared the break-even point plus a 500 ETB safety buffer.

### 📦 Inventory Manager
* **Low-Stock Basket:** Automatically flags items with 5 or fewer units remaining.
* **Automated Stock Tracking:** Inventory seamlessly deducts upon sale and restores upon a voided/cancelled transaction using secure Firestore merge logic.
* **Capital Asset Tracking:** Calculates the total ETB value of all active inventory and the locked capital sitting in the low-stock basket.

---

## 🛠 Tech Stack

* **Frontend:** Flutter (Optimized for Android)
* **Backend / Database:** Firebase (Cloud Firestore & Firebase Auth)
* **State Management:** Riverpod (`flutter_riverpod`)
* **Native Integrations:** `share_plus` (for CSV File Exporting via Android Share Sheet)

---

## 🗄️ Firestore Database Schema

To set this project up from scratch, your Firestore database should contain the following collections:

### `users`
```json
{
  "email": "admin@shop.com",
  "role": "admin" // or "worker"
}

inventory
{
  "name": "Tecno Spark 20",
  "base_cost": 8500.0,
  "stock_quantity": 10,
  "is_active": true
}

expenses 
{
  "worker_id": "khalid",
  "category": "Transport (Essential)",
  "amount": 150.0,
  "reason": "Taxi to warehouse",
  "timestamp": "serverTimestamp()"
}

sales

{
  "worker_id": "khalid",
  "item_id": "doc_id_from_inventory",
  "item_name": "Tecno Spark 20",
  "base_cost": 8500.0, 
  "final_price": 9000.0,
  "quantity": 1,
  "payment_method": "Telebirr",
  "timestamp": "serverTimestamp()",
  "is_loss_override": false
}

🚀 Setup & Installation

    Clone the Repository
        git clone [https://github.com/KHALIDKHELIL/kiosk-pos.git](https://github.com/KHALIDKHELIL/kiosk-pos.git)
        cd kiosk-pos


Install Dependencies
    flutter pub get


Configure Firebase

    Create a new project in the Firebase Console.

    Enable Firestore Database and Authentication (Email/Password).

    Run the FlutterFire CLI to link your project:
        flutterfire configure

Run the App
    flutter run


👨‍💻 Author

Developed and maintained by KHALIDKHELIL