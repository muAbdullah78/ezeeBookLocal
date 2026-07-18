# EzeeBook Release Keystore

## Generate the keystore (run this command in terminal):

```
keytool -genkey -v -keystore C:\dev\ezeebook\android\app\ezeebook-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ezeebook
```

When prompted, enter:
- **Keystore password:** [choose a strong password and WRITE IT DOWN]
- **Key password:** [same as keystore password is fine]
- **First and last name:** Muhammad Abdullah
- **Organization unit:** Development
- **Organization:** Usconnect Solutions
- **City:** Rawalpindi
- **State:** Punjab
- **Country code:** PK

## IMPORTANT: Save these files and passwords safely!

- `ezeebook-release-key.jks` — NEVER lose this file
- Keystore password — NEVER forget this
- Key alias: `ezeebook`

**Without these, you can NEVER update your app on Play Store.**

## After generating, create `android/key.properties`:

```
storePassword=YOUR_PASSWORD_HERE
keyPassword=YOUR_PASSWORD_HERE
keyAlias=ezeebook
storeFile=../app/ezeebook-release-key.jks
```
