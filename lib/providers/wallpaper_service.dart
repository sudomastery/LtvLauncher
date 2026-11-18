/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _fLauncherChannel;
  final SettingsService _settingsService;

  late File _wallpaperFile;
  late File _wallpaperDayFile;
  late File _wallpaperNightFile;
  Timer? _timer;

  // Slideshow: pictures are read from <app external files dir>/wallpapers.
  static const _slideshowFolderName = "wallpapers";
  static const _imageExtensions = {".jpg", ".jpeg", ".png", ".webp"};
  /// Built-in wallpapers, shown when the user has not added pictures or chosen a gradient or picture.
  static const _defaultAssets = [
    'assets/wallpapers/aurora.jpg',
    'assets/wallpapers/ocean.jpg',
    'assets/wallpapers/sunset.jpg',
    'assets/wallpapers/ember.jpg',
  ];
  int _defaultIndex = -1;
  Directory? _slideshowDirectory;
  List<File> _slideshowFiles = [];
  int _slideshowIndex = -1;
  Timer? _slideshowTimer;
  DateTime _lastSlideshowChange = DateTime.fromMillisecondsSinceEpoch(0);
  bool _slideshowActive = false;
  int _restartGeneration = 0; // a restart that is no longer the latest stops instead of making a second timer
  int _lastSlideshowMinutes = 0;
  bool _lastSlideshowEnabled = false;
  bool _initialized = false;

  // Decoded size is capped at the display width so a 4K picture does not cost 4K of RAM.
  final Map<String, ImageProvider> _providers = {};

  ImageProvider? _wallpaper;
  int _version = 0;
  int _updateWallpaperCallCount = 0;

  ImageProvider?  get wallpaper     => _wallpaper;
  int             get version       => _version;

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.pitchBlack,
      );

  WallpaperService(this._fLauncherChannel, this._settingsService) :
    _wallpaper = null
  {
    _settingsService.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  bool _lastTimeBasedEnabled = false;

  /// Folder the slideshow reads from, or null before it is known. Shown in the settings screen.
  String? get slideshowFolderPath => _slideshowDirectory?.path;

  /// Number of pictures found in the slideshow folder at the last refresh.
  int get slideshowPictureCount => _slideshowFiles.length;

  void _onSettingsChanged() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled != _lastTimeBasedEnabled) {
      _lastTimeBasedEnabled = enabled;
      _updateTimerState();
      _updateWallpaper();
    }
    if (!_initialized) return;
    final slideshowEnabled = _settingsService.wallpaperSlideshowEnabled;
    final minutes = _settingsService.wallpaperSlideshowMinutes;
    if (slideshowEnabled != _lastSlideshowEnabled || minutes != _lastSlideshowMinutes) {
      _lastSlideshowEnabled = slideshowEnabled;
      _lastSlideshowMinutes = minutes;
      _restartSlideshow(advanceNow: slideshowEnabled);
    }
  }

  @override
  void didChangeAppLifecycleState(ui.AppLifecycleState state) {
    if (!_initialized) return;
    // Only run the slideshow while the launcher is on screen: no timers or decoding while an app is in front.
    if (state == ui.AppLifecycleState.resumed) {
      if (_settingsService.wallpaperSlideshowEnabled) {
        final due = DateTime.now().difference(_lastSlideshowChange) >=
            Duration(minutes: _settingsService.wallpaperSlideshowMinutes);
        _restartSlideshow(advanceNow: due);
      }
    } else if (state == ui.AppLifecycleState.paused || state == ui.AppLifecycleState.hidden) {
      _slideshowTimer?.cancel();
      _slideshowTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsService.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _slideshowTimer?.cancel();
    super.dispose();
  }

  int get _decodeWidth {
    try {
      final physical = ui.PlatformDispatcher.instance.views.first.physicalSize.width;
      return min(physical.round(), 1920);
    } catch (_) {
      return 1280;
    }
  }

  /// One provider instance per file, decoded no wider than the screen.
  ImageProvider _providerFor(File file) {
    return _providers.putIfAbsent(
      file.path,
      () => ResizeImage(FileImage(file), width: _decodeWidth, allowUpscaling: false),
    );
  }

  ImageProvider _assetProvider(String path) {
    return _providers.putIfAbsent(
      path,
      () => ResizeImage(AssetImage(path), width: _decodeWidth, allowUpscaling: false),
    );
  }

  /// The built-in wallpapers are used only while the user has not picked anything of their own.
  Future<bool> _defaultsAllowed() async {
    if (_settingsService.gradientUuid != null) return false; // an explicit gradient choice wins
    if (await _wallpaperFile.exists()) return false;
    return true;
  }

  Future<void> _advanceDefault() async {
    final previous = _defaultIndex >= 0 ? _defaultAssets[_defaultIndex] : null;
    _defaultIndex = (_defaultIndex + 1) % _defaultAssets.length;
    final provider = _assetProvider(_defaultAssets[_defaultIndex]);
    await _preload(provider);
    _lastSlideshowChange = DateTime.now();
    _wallpaper = provider;
    _version++;
    notifyListeners();
    if (previous != null && previous != _defaultAssets[_defaultIndex]) {
      await _providers.remove(previous)?.evict();
    }
  }

  Future<void> _forget(File file) async {
    final old = _providers.remove(file.path);
    await old?.evict();
    await FileImage(file).evict();
  }

  Future<void> _preload(ImageProvider provider) {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) {
        if (!completer.isCompleted) completer.complete();
        stream.removeListener(listener);
      },
      onError: (_, __) {
        if (!completer.isCompleted) completer.complete();
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  Future<void> _refreshSlideshowFiles() async {
    final directory = _slideshowDirectory;
    if (directory == null) return;
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final files = <File>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && _imageExtensions.contains(_extensionOf(entity.path))) {
          files.add(entity);
        }
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      files.shuffle(Random());
      _slideshowFiles = files;
      _slideshowIndex = -1;
    } catch (_) {
      _slideshowFiles = [];
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  /// Re-reads the slideshow folder and shows the next picture (used by the settings screen).
  Future<void> rescanSlideshow() => _restartSlideshow(advanceNow: true);

  /// (Re)starts the slideshow timer and optionally shows the next picture immediately.
  Future<void> _restartSlideshow({required bool advanceNow}) async {
    final generation = ++_restartGeneration;
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    final enabled = _settingsService.wallpaperSlideshowEnabled;
    _slideshowActive = false;
    if (!enabled) {
      _lastSlideshowEnabled = false;
      _slideshowFiles = [];
      _providers.clear();
      await _updateWallpaper(force: true);
      return;
    }
    if (_slideshowDirectory == null) {
      await _updateWallpaper(force: true);
      return;
    }
    await _refreshSlideshowFiles();
    if (generation != _restartGeneration) return; // a newer restart took over while the folder was read
    if (_slideshowFiles.isEmpty) {
      final defaultsAllowed = await _defaultsAllowed();
      if (generation != _restartGeneration) return;
      if (!defaultsAllowed) {
        await _updateWallpaper(force: true);
        return;
      }
      // Nothing of the user's yet: rotate the built-in wallpapers on the same timer.
      _slideshowActive = true;
      _slideshowTimer = Timer.periodic(
        Duration(minutes: _settingsService.wallpaperSlideshowMinutes),
        (_) => _advanceSlideshow(),
      );
      if (advanceNow || _wallpaper == null) await _advanceDefault();
      return;
    }
    _slideshowActive = true;
    _slideshowTimer = Timer.periodic(
      Duration(minutes: _settingsService.wallpaperSlideshowMinutes),
      (_) => _advanceSlideshow(),
    );
    if (advanceNow || _wallpaper == null) {
      await _advanceSlideshow();
    }
  }

  Future<void> _advanceSlideshow() async {
    if (_slideshowFiles.isEmpty) {
      if (await _defaultsAllowed()) await _advanceDefault();
      return;
    }
    final previous = _slideshowIndex >= 0 && _slideshowIndex < _slideshowFiles.length ? _slideshowFiles[_slideshowIndex] : null;
    _slideshowIndex = (_slideshowIndex + 1) % _slideshowFiles.length;
    final next = _slideshowFiles[_slideshowIndex];
    final provider = _providerFor(next);
    await _preload(provider);
    _lastSlideshowChange = DateTime.now();
    _wallpaper = provider;
    _version++;
    notifyListeners();
    if (previous != null && previous.path != next.path) {
      // Keep at most the current picture decoded in memory.
      await _forget(previous);
    }
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _wallpaperFile = File("${directory.path}/wallpaper");
    _wallpaperDayFile = File("${directory.path}/wallpaper_day");
    _wallpaperNightFile = File("${directory.path}/wallpaper_night");
    _initialized = true;

    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        _slideshowDirectory = Directory("${external.path}/$_slideshowFolderName");
        if (!await _slideshowDirectory!.exists()) {
          await _slideshowDirectory!.create(recursive: true);
        }
      }
    } catch (_) {
      _slideshowDirectory = null;
    }

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _lastSlideshowEnabled = _settingsService.wallpaperSlideshowEnabled;
    _lastSlideshowMinutes = _settingsService.wallpaperSlideshowMinutes;
    if (_lastSlideshowEnabled) {
      await _restartSlideshow(advanceNow: true);
    } else {
      await _updateWallpaper();
    }
    _updateTimerState();
  }

  void _updateTimerState() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled && (_timer == null || !_timer!.isActive)) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateWallpaper());
    } else if (!enabled && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _updateWallpaper({bool force = false}) async {
    final callId = ++_updateWallpaperCallCount;
    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    ImageProvider? newWallpaper;

    if (_slideshowActive && _wallpaper != null) {
      // The slideshow owns the wallpaper while it is running; _advanceSlideshow sets it.
      return;
    }

    if (enabled) {
      if (isDay && await _wallpaperDayFile.exists()) {
        newWallpaper = _providerFor(_wallpaperDayFile);
      } else if (!isDay && await _wallpaperNightFile.exists()) {
        newWallpaper = _providerFor(_wallpaperNightFile);
      } else if (await _wallpaperFile.exists()) {
        newWallpaper = _providerFor(_wallpaperFile); // Fallback
      }
    } else {
      if (await _wallpaperFile.exists()) {
        newWallpaper = _providerFor(_wallpaperFile);
      }
    }

    // Nothing of the user's and no gradient chosen: show a built-in wallpaper instead of plain black.
    if (newWallpaper == null && await _defaultsAllowed()) {
      if (_defaultIndex < 0) _defaultIndex = 0;
      newWallpaper = _assetProvider(_defaultAssets[_defaultIndex]);
    }

    if (callId == _updateWallpaperCallCount) {
      if (_wallpaper != newWallpaper || force) {
        _wallpaper = newWallpaper;
        notifyListeners();
      }
    }
  }

  Future<void> pickWallpaper() async {
    await _pickAndSave(_wallpaperFile);
  }

  Future<void> pickWallpaperDay() async {
    await _pickAndSave(_wallpaperDayFile);
  }

  Future<void> pickWallpaperNight() async {
    await _pickAndSave(_wallpaperNightFile);
  }

  Future<void> _pickAndSave(File targetFile) async {
    if (!await _fLauncherChannel.checkForGetContentAvailability()) {
      throw NoFileExplorerException();
    }

    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // Use stream for memory efficiency
      final readStream = pickedFile.openRead();
      final writeStream = targetFile.openWrite();
      await readStream.cast<List<int>>().pipe(writeStream);

      // Evict from cache to ensure UI updates
      await _forget(targetFile);

      _version++;
      // Not _updateWallpaper: while the built-in wallpapers rotate the slideshow owns the wallpaper and would
      // ignore the new picture. Restarting hands control back when the user now has something of their own.
      await _restartSlideshow(advanceNow: false);
    }
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    _settingsService.setGradientUuid(fLauncherGradient.uuid);
    // An explicit gradient ends the built-in wallpaper rotation; without this the old picture stays on screen.
    await _restartSlideshow(advanceNow: false);
    notifyListeners();
  }
}

class NoFileExplorerException implements Exception {}
