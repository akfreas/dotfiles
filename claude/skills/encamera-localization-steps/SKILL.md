---
name: ios-localization-steps
description: >-
  Add user-facing strings to the Encamera iOS app via the Localizable.strings →
  SwiftGen → L10n pipeline. Invoke whenever adding, editing, or referencing a
  UI string in EncameraCore or any iOS target that consumes L10n.
---

# iOS Localization Steps

When you add strings to the app, you MUST follow this pipeline:

## 1. Add the string to the English source file

Edit `/Users/akfreas/github/EncameraApp/EncameraCore/Sources/EncameraCore/Resources/en.lproj/Localizable.strings`.

- Place the new key in the appropriate existing section, or create a new section if no section fits.
- Follow the existing naming convention (dot-separated, PascalCase segments, e.g. `PhotoPickerWrapper.ContinueLimited`).

## 2. Regenerate the L10n type

Run SwiftGen from the EncameraCore directory:

```sh
cd /Users/akfreas/github/EncameraApp/EncameraCore && swiftgen
```

This updates `Strings+Generated.swift`, which exposes the new key on the `L10n` object.

## 3. Reference the string via L10n

SwiftGen lowercases the **first letter** of the final segment. So a key like:

```
PhotoPickerWrapper.ContinueLimited
```

is referenced in code as:

```swift
L10n.PhotoPickerWrapper.continueLimited
```

Always use `L10n.…` in code — never hardcode the raw string.

## 4. Do NOT translate

Do **not** add translations to other `*.lproj/Localizable.strings` files. Translations are handled in a separate later step.
