# casus_flutter example

A small profile page exercising `ResourceBuilder` across all three
`Resource` states — including stale-while-revalidate: a "Reload (fails)"
button that keeps the last-loaded name on screen, wrapped in an error
banner, instead of collapsing the whole page to a retry view.

Run it with:

```
flutter pub get
flutter run
```

`lib/main.dart` is the entire app.
