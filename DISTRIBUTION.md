# Building and selling EzeeBook

Everything needed to put the app on a tailor's phone, plus answers to the
questions shop owners actually ask.

---

## 1. One-time setup on your laptop

You only ever do this **once**. Do it before you sell a single copy.

### 1a. Create your signing key

Android refuses to install an app that is not signed, and — this is the part
that matters — **an update must be signed with the same key as the original
install**. If you hand out copies signed with one key and later switch to
another, existing customers cannot update. They would have to uninstall first,
**and uninstalling deletes all their data**. So make this key now, and never
lose it.

```bash
keytool -genkey -v -keystore ezeebook-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ezeebook
```

It asks for a password and your name/city. Answer them and **write the password
down somewhere permanent**.

Move `ezeebook-release.jks` somewhere outside the project folder, e.g.
`F:\dev\ezeebook-secrets\`.

### 1b. Point the project at the key

Create a file called `key.properties` in the project root (next to
`pubspec.yaml`) containing:

```properties
storePassword=THE_PASSWORD_YOU_CHOSE
keyPassword=THE_PASSWORD_YOU_CHOSE
keyAlias=ezeebook
storeFile=F:\\dev\\ezeebook-secrets\\ezeebook-release.jks
```

Use double backslashes in the path on Windows.

`key.properties` and `*.jks` are already in `.gitignore` — they must **never**
be committed to GitHub. Anyone with that file can publish updates pretending to
be you.

> Back up the `.jks` file and the password to a USB stick and to your own Drive.
> Losing them means you can never update the app for any customer you have
> already sold to.

### 1c. Refresh the app icon (optional)

The launcher icon is already generated from your logo. If you change the logo,
replace `assets/images/app_icon.png` (1024×1024) and run:

```bash
dart run flutter_launcher_icons
```

---

## 2. Build the APK

```bash
flutter clean
flutter pub get
flutter build apk --release
```

The file appears at:

```
build\app\outputs\flutter-apk\app-release.apk
```

That single file **is** the product. Copy it somewhere handy.

If the build stops with *"key.properties is missing"*, step 1b was skipped —
that check exists on purpose, so you can never accidentally ship a copy signed
with a throwaway debug key.

### Smaller downloads (optional)

```bash
flutter build apk --release --split-per-abi
```

This produces one APK per phone type. `app-arm64-v8a-release.apk` covers almost
every phone sold in the last several years and is roughly half the size. If you
are unsure which to hand over, use the single `app-release.apk` — it works
everywhere.

---

## 3. Install it on a tailor's phone

Pick whichever is easiest in the shop.

**Option A — USB cable (fastest, most reliable)**

1. Enable Developer Options on the phone: Settings → About phone → tap **Build
   number** seven times.
2. Settings → Developer options → turn on **USB debugging**.
3. Plug the phone into your laptop, accept the "Allow USB debugging" prompt.
4. Run: `flutter install` (or `adb install -r build\app\outputs\flutter-apk\app-release.apk`)

**Option B — send the file (no cable needed)**

1. Send `app-release.apk` to the tailor by WhatsApp, Bluetooth, Google Drive,
   or copy it with a USB stick / SHAREit.
2. On the phone, open the file from Downloads or the Files app.
3. Android will say *"For your security, your phone is not allowed to install
   unknown apps from this source."* Tap **Settings** → turn on **Allow from
   this source** → back → **Install**.
4. Android may show *"Play Protect doesn't recognise this app"*. Tap **Install
   anyway**. This is normal for any app not downloaded from the Play Store; it
   is not a warning about anything being wrong with your app.

Then open it once with them and walk through the first-run screens:
disclaimer → shop details → optional PIN.

**Option C — carry a USB stick** with the APK on it. Same as option B from
step 2. Useful where the shop has no data connection.

### What to do on the very first visit

1. Install it.
2. Set up their shop name, owner name and phone — this prints on every receipt.
3. Set up their stitching categories with them (Settings → Shop → Stitching
   Categories). Doing this together is the moment they realise the app is
   *theirs*, and it is your strongest selling point.
4. Add one real customer and place one real order end to end.
5. Show them Backup, and tell them to do it every couple of weeks. The app will
   also remind them.

---

## 4. Questions shop owners will ask

**"Where is my data kept?"**
On your phone, and nowhere else. There is no company server, no internet
account, nothing sent anywhere. Customer names, measurements and orders are
saved in the app's own private storage on that handset. Not even you as the
seller can see them.

**"Does it need internet?"**
No. Everything — adding customers, taking measurements, placing orders,
printing the receipt PDF — works with the phone in aeroplane mode. Internet is
only used if they choose to send a WhatsApp message to a customer, which is
WhatsApp's job, not the app's.

**"Is it a monthly fee?"**
No. One payment, and the app is theirs. Nothing expires, nothing locks, there
is no subscription and no renewal.

**"What if I change my phone?"**
Straightforward, and they should do it in this order:
1. On the **old** phone: Settings → **Backup Data**. This creates one file.
   Send it to themselves by WhatsApp, or save it to Google Drive, or copy it to
   a USB/memory card.
2. Install EzeeBook on the **new** phone (you do this, or they do it from the
   APK you gave them).
3. On the **new** phone: Settings → **Restore Data** → pick that file.
Everything comes across: customers, orders, measurements, their categories, the
shop profile. Tell them plainly: **do the backup before getting rid of the old
phone**, because there is no other copy.

**"Can I use it on two phones at once — my shop phone and my own?"**
Not as one shared register, and it is worth being honest about why. Each
install is completely separate with its own data, and there is no server to
keep two phones in step. If they add a customer on phone A, phone B will never
know. They *can* copy everything from one to the other with the same
Backup/Restore file, but that is a one-way snapshot, not live syncing — and
restoring **replaces** everything on the receiving phone, so anything typed
there since is lost.

Practical advice: one phone is the shop's register. If they want the data on a
second phone, treat it as a copy for viewing, not for taking new orders.

**"What if my phone is lost or stolen or breaks?"**
This is the honest risk of having no cloud, and they should hear it from you
rather than discover it. If there is no backup file, the data is gone. That is
why the app reminds them to take a backup and why they should keep the file in
their own WhatsApp or Drive. Tell them to do it on the first of every month.

**"Can someone else open my phone and see my customers?"**
They can switch on a 4-digit PIN (Settings → App Lock). The app then asks for
it on opening and again after the phone has been idle. The PIN is stored
scrambled, not as plain text.

**"Is my customers' data safe?"**
It never leaves the handset. The app has no login, collects nothing, and sends
nothing anywhere. It is also excluded from Google's automatic phone backup, so
it does not get copied to a Google account behind their back.

**"Will you keep fixing it?"**
Say what you actually intend, and say it the same way every time. The app is
sold as-is (the disclaimer they accept on first launch says this). If you plan
to hand out improvements, tell them you will bring a new file — and remember
that an update needs the **same signing key**, which is why step 1a matters.

**"Can I use it in Urdu?"**
Yes — Settings → Language → اردو. It switches the whole app.

---

## 5. Before you walk into the first shop

- [ ] `flutter build apk --release` finishes and produces the APK
- [ ] Install it on **your own** phone first and use it for a full day
- [ ] Place a real order end to end and print the PDF
- [ ] Check the receipt shows every measurement — and **no prices** (the worker
      copy deliberately has no money on it)
- [ ] Take a backup on one phone, restore it on another, confirm everything
      arrives
- [ ] Try it in Urdu and check the screens still read properly
- [ ] Set a PIN, close the app, reopen it, confirm it asks
- [ ] Keep a spare copy of the APK on your phone so you can install in a shop
      with no laptop
