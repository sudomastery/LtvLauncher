# Changes from the original

### Features
* Allow users to customize the date widget format, making it possible to display the [date, time](https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html), and any arbitrary text, or to hide it completely.
* Choose what the back button does while being in the launcher: Nothing, Show a fullscreen clock, Show screensaver (a.k.a Ambient Mode).
* Show the active network status next to the date widget.
* Allow users to hide the application category titles.
* Clicking or tapping on an application card now opens it.
* Ability to disable the navigation keys sound.
* The app bar can now hide automatically while not focused.
* Map "Escape" key to the "Back" action.
* Translate to Spanish.

* Wallpaper slideshow: pictures in `Android/data/<app id>/files/wallpapers` rotate every 1 minute to 24 hours (default 15 minutes), only while the launcher is on screen. Wallpapers are decoded at the screen width, so a 4K picture does not cost 4K of RAM.
* Showcase home screen (default): the wallpaper fills the screen with one row of Favorites along the bottom. Down opens the full apps view, Back returns.
* Default Favorites: TizenTube, Plex, Prime Video, Netflix, Spotify and Twitch appear in that order when installed, and are added later if installed later.
* Glow is the default card theme.

### Removals
* Firebase analytics and crashlytics services.
* Unsplash integration.

### Misc
* Upgrade Flutter version from 3.7.5 to 3.24.5.
* Replace Kotlin code with Java.
* Set new language versions: Java (17), Dart (greater than or equal to 3.4.3).
* Change versioning scheme to \<year>.\<month>.\<monthly release number>
