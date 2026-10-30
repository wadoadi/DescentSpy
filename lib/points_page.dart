import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'gps_position_service.dart';
import 'point_data.dart';

enum _PointFilter { all, favourites, airfields, towns, ports, vrps }

enum PointSearchKeyboardMode { large, system }

const pointSearchKeyboardPreferenceKey = 'point_search_keyboard_mode';

class PointFinderPage extends StatefulWidget {
  const PointFinderPage({super.key, this.selectForDistance = false});

  final bool selectForDistance;

  @override
  State<PointFinderPage> createState() => _PointFinderPageState();
}

class _PointFinderPageState extends State<PointFinderPage> {
  static const _airfieldsAsset = 'assets/airfields_uk.json';
  static const _townsAsset = 'assets/places_uk.json';
  static const _vrpsAsset = 'assets/UK-VRPs.csv';
  static const _customPointsKey = 'navigation_custom_points';
  static const _favouritesKey = 'navigation_favourite_ids';

  final _search = TextEditingController();
  final List<NavigationPoint> _catalogue = [];
  final List<NavigationPoint> _customPoints = [];
  final Set<String> _favouriteIds = {};
  Timer? _staleTimer;
  Position? _position = GpsPositionService.instance.position;
  NavigationPoint? _selectedPoint;
  _PointFilter _filter = _PointFilter.all;
  String? _locationMessage =
      GpsPositionService.instance.errorMessage ??
      (GpsPositionService.instance.position == null
          ? 'Getting current location…'
          : null);
  String? _dataError;
  String? _saveMessage;
  bool _loading = true;
  bool _locationStale = _isPositionStale(GpsPositionService.instance.position);
  bool _searchKeyboardOpen = false;
  bool _loadStarted = false;
  PointSearchKeyboardMode _keyboardMode = PointSearchKeyboardMode.large;

  @override
  void initState() {
    super.initState();
    GpsPositionService.instance.addListener(_onGpsServiceChanged);
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final position = _position;
      final stale =
          position == null ||
          DateTime.now().difference(position.timestamp) >
              const Duration(seconds: 10);
      if (mounted) {
        setState(() => _locationStale = stale);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(_loadData(DefaultAssetBundle.of(context)));
    }
  }

  @override
  void dispose() {
    GpsPositionService.instance.removeListener(_onGpsServiceChanged);
    _search.dispose();
    _staleTimer?.cancel();
    super.dispose();
  }

  static bool _isPositionStale(Position? position) =>
      position == null ||
      DateTime.now().difference(position.timestamp) >
          const Duration(seconds: 10);

  void _onGpsServiceChanged() {
    if (!mounted) return;
    final service = GpsPositionService.instance;
    setState(() {
      if (service.position != null) _position = service.position;
      _locationStale = _isPositionStale(_position);
      _locationMessage =
          service.errorMessage ??
          (_position == null ? 'Getting current location…' : null);
    });
  }

  Future<void> _loadData(AssetBundle assetBundle) async {
    try {
      final airfields = jsonDecode(
        await assetBundle.loadString(_airfieldsAsset),
      ) as List<dynamic>;
      final towns = jsonDecode(
        await assetBundle.loadString(_townsAsset),
      ) as List<dynamic>;
      final vrpCsv = await assetBundle.loadString(_vrpsAsset);
      final points = <NavigationPoint>[
        for (final entry in airfields)
          _cataloguePoint(
            entry as Map<String, dynamic>,
            PointCategory.airfield,
          ),
        for (final entry in towns)
          _cataloguePoint(entry as Map<String, dynamic>, PointCategory.town),
        ..._parseVrps(vrpCsv),
      ];
      final uniquePoints = deduplicateNavigationPoints(points);
      final preferences = await SharedPreferences.getInstance();
      final customJson = preferences.getString(_customPointsKey);
      final custom = customJson == null
          ? <NavigationPoint>[]
          : (jsonDecode(customJson) as List<dynamic>)
                .map(
                  (entry) =>
                      NavigationPoint.fromJson(entry as Map<String, dynamic>),
                )
                .toList();
      final uniqueCustomPoints = deduplicateNavigationPoints(custom);
      if (!mounted) return;
      setState(() {
        _catalogue
          ..clear()
          ..addAll(uniquePoints);
        _customPoints
          ..clear()
          ..addAll(uniqueCustomPoints);
        _favouriteIds
          ..clear()
          ..addAll(preferences.getStringList(_favouritesKey) ?? const []);
        _keyboardMode =
            preferences.getString(pointSearchKeyboardPreferenceKey) ==
                PointSearchKeyboardMode.system.name
            ? PointSearchKeyboardMode.system
            : PointSearchKeyboardMode.large;
        _loading = false;
      });
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _dataError = 'Could not read bundled point data: $error';
          _loading = false;
        });
      }
    } on FlutterError catch (error) {
      if (mounted) {
        setState(() {
          _dataError = 'Point data is missing from the app bundle: $error';
          _loading = false;
        });
      }
    }
  }

  NavigationPoint _cataloguePoint(
    Map<String, dynamic> entry,
    PointCategory category,
  ) {
    final name = entry['name'] as String;
    final latitude = (entry['lat'] as num).toDouble();
    final longitude = (entry['lon'] as num).toDouble();
    final icao = entry['icao'] as String? ?? '';
    final identity = icao.isNotEmpty
        ? icao
        : '${name.toLowerCase()}_${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}';
    return NavigationPoint(
      id: '${category.name}:$identity',
      name: name,
      category: category,
      latitude: latitude,
      longitude: longitude,
      icao: icao,
    );
  }

  List<NavigationPoint> get _allPoints {
    final points = deduplicateNavigationPoints([
      ..._catalogue,
      ..._customPoints,
    ]);
    final position = _locationStale ? null : _position;
    return sortNavigationPoints(
      points: points,
      fromLatitude: position?.latitude,
      fromLongitude: position?.longitude,
    );
  }

  List<NavigationPoint> get _visiblePoints {
    final query = _search.text.trim().toLowerCase();
    final points = _allPoints.where((point) {
      final matchesFilter = switch (_filter) {
        _PointFilter.all => true,
        _PointFilter.favourites => _favouriteIds.contains(point.id),
        _PointFilter.airfields => point.category == PointCategory.airfield,
        _PointFilter.towns => point.category == PointCategory.town,
        _PointFilter.ports => point.category == PointCategory.port,
        _PointFilter.vrps => point.category == PointCategory.vrp,
      };
      return matchesFilter;
    }).toList();
    final position = _locationStale ? null : _position;
    return searchNavigationPoints(
      points: points,
      query: query,
      fromLatitude: position?.latitude,
      fromLongitude: position?.longitude,
    );
  }

  void _openSearchKeyboard() {
    FocusScope.of(context).unfocus();
    setState(() => _searchKeyboardOpen = true);
  }

  void _closeSearchKeyboard() {
    setState(() => _searchKeyboardOpen = false);
  }

  Future<void> _toggleFavourite(NavigationPoint point) async {
    setState(() {
      if (!_favouriteIds.add(point.id)) _favouriteIds.remove(point.id);
    });
    await _savePoints();
  }

  Future<void> _savePoints() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _customPointsKey,
        jsonEncode(_customPoints.map((point) => point.toJson()).toList()),
      );
      await preferences.setStringList(_favouritesKey, _favouriteIds.toList());
      if (mounted) setState(() => _saveMessage = null);
    } catch (error) {
      if (mounted) {
        setState(() => _saveMessage = 'Could not save points: $error');
      }
    }
  }

  Future<void> _addPoint({
    PointCategory initialCategory = PointCategory.vrp,
  }) async {
    final point = await showDialog<NavigationPoint>(
      context: context,
      builder: (context) => _PointEditor(initialCategory: initialCategory),
    );
    if (point == null) return;
    setState(() {
      _customPoints.add(point);
      _favouriteIds.add(point.id);
      _selectedPoint = point;
      _filter = switch (point.category) {
        PointCategory.airfield => _PointFilter.airfields,
        PointCategory.town => _PointFilter.towns,
        PointCategory.port => _PointFilter.ports,
        PointCategory.vrp => _PointFilter.vrps,
      };
    });
    await _savePoints();
  }

  Future<void> _clearMyPoints() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved points?'),
        content: const Text(
          'This removes your custom points and saved favourites. The bundled airfield and town list remains.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _customPoints.clear();
      _favouriteIds.clear();
      _selectedPoint = null;
      _filter = _PointFilter.all;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_customPointsKey);
      await preferences.remove(_favouritesKey);
      if (mounted) setState(() => _saveMessage = null);
    } catch (error) {
      if (mounted) {
        setState(() => _saveMessage = 'Could not clear saved points: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final stale = _locationStale;
    final keyboardHeight = math.min(
      460.0,
      MediaQuery.sizeOf(context).height * 0.7,
    );
    final systemKeyboardOpen =
        _keyboardMode == PointSearchKeyboardMode.system &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactSearch = _searchKeyboardOpen || systemKeyboardOpen;
    final range = position == null || _selectedPoint == null
        ? null
        : calculatePointRange(
            fromLatitude: position.latitude,
            fromLongitude: position.longitude,
            toLatitude: _selectedPoint!.latitude,
            toLongitude: _selectedPoint!.longitude,
          );

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            bottom: _searchKeyboardOpen ? keyboardHeight + 10 : 0,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compactSearch ? 8 : 14,
                      16,
                      6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compactSearch) ...[
                          const Text(
                            'DESTINATION POINTS',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.selectForDistance
                                ? 'Select a destination to use its direct GPS distance.'
                                : 'Select a UK airfield or town, save favourites, or add a port / VRP with coordinates.',
                            style: TextStyle(
                              color: context.appSecondaryText,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _locationStatus(position, stale),
                          if (_selectedPoint != null) ...[
                            const SizedBox(height: 10),
                            _selectedPointCard(_selectedPoint!, range, stale),
                          ],
                          const SizedBox(height: 10),
                          if (!widget.selectForDistance) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: FilledButton.icon(
                                      onPressed: _addPoint,
                                      icon: const Icon(
                                        Icons.add_location_alt,
                                        size: 22,
                                      ),
                                      label: const Text(
                                        'ADD POINT',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: context.appAccent,
                                        foregroundColor: context.appBackground,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  tooltip:
                                      'Clear all custom points and favourites',
                                  onPressed: _clearMyPoints,
                                  icon: const Icon(Icons.delete_sweep_outlined),
                                ),
                                const SizedBox(width: 4),
                                IconButton.filledTonal(
                                  tooltip: 'Refresh location',
                                  onPressed: () {
                                    unawaited(
                                      GpsPositionService.instance.restart(),
                                    );
                                  },
                                  icon: const Icon(Icons.my_location),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (widget.selectForDistance)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Tap a destination to use its direct GPS distance.',
                                style: TextStyle(
                                  color: context.appAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                        TextField(
                          controller: _search,
                          readOnly:
                              _keyboardMode == PointSearchKeyboardMode.large,
                          onTap: _keyboardMode == PointSearchKeyboardMode.large
                              ? _openSearchKeyboard
                              : null,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search points or ICAO',
                            suffixIcon: IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                          ),
                        ),
                        if (!compactSearch) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _filterChip(_PointFilter.all, 'ALL'),
                              _filterChip(
                                _PointFilter.favourites,
                                'FAVOURITES',
                              ),
                              _filterChip(_PointFilter.airfields, 'AIRFIELDS'),
                              _filterChip(_PointFilter.towns, 'TOWNS'),
                              _filterChip(_PointFilter.ports, 'PORTS'),
                              _filterChip(_PointFilter.vrps, 'VRPs'),
                            ],
                          ),
                          if (_dataError != null || _saveMessage != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _dataError ?? _saveMessage!,
                              style: const TextStyle(color: Color(0xFFFF6B6B)),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_visiblePoints.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _filter == _PointFilter.vrps &&
                                      !widget.selectForDistance
                                  ? 'No VRPs have been added yet. Add one using a current chart.'
                                  : 'No points match this filter.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.appSecondaryText,
                                fontSize: 16,
                              ),
                            ),
                            if (!widget.selectForDistance &&
                                _filter == _PointFilter.vrps) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _addPoint(),
                                icon: const Icon(Icons.add_location_alt),
                                label: const Text('ADD VRP'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    sliver: SliverList.builder(
                      itemCount: _visiblePoints.length,
                      itemBuilder: (context, index) =>
                          _pointRow(_visiblePoints[index]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
                      child: Text(
                        'Airfields: OurAirports (public domain). Towns: GeoNames GB (CC BY 4.0). VRPs: user-supplied UK-VRPs.csv with valid-from dates. Verify every VRP against current official charts/AIP before use.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.appFaintText,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_searchKeyboardOpen)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LargeSearchKeyboard(
                  height: keyboardHeight,
                  initialValue: _search.text,
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _search.text = value);
                  },
                  onClose: _closeSearchKeyboard,
                  onSearch: _closeSearchKeyboard,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _locationStatus(Position? position, bool stale) {
    final message = _locationMessage;
    if (position == null || stale || message != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appPanel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              stale ? Icons.location_searching : Icons.location_on,
              color: context.appWarning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stale && message == null
                    ? 'GPS fix is stale. Waiting for a fresh location.'
                    : message ?? 'Waiting for a GPS fix.',
                style: TextStyle(color: context.appSecondaryText),
              ),
            ),
            TextButton(
              onPressed: () {
                unawaited(GpsPositionService.instance.restart());
              },
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Icon(Icons.my_location, color: context.appAccent, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'GPS ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)} · ±${position.accuracy.round()} m',
            style: TextStyle(color: context.appSecondaryText, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _selectedPointCard(
    NavigationPoint point,
    PointRange? range,
    bool stale,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appAccent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place, color: context.appAccent),
              if (!stale && range != null) ...[
                const SizedBox(width: 4),
                Transform.rotate(
                  angle: range.bearingDeg * math.pi / 180,
                  child: Icon(
                    Icons.navigation,
                    color: context.appAccent,
                    size: 22,
                    semanticLabel: 'Bearing to destination',
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  point.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: _favouriteIds.contains(point.id)
                    ? 'Remove favourite'
                    : 'Add favourite',
                onPressed: () => unawaited(_toggleFavourite(point)),
                icon: Icon(
                  _favouriteIds.contains(point.id)
                      ? Icons.star
                      : Icons.star_border,
                  color: context.appWarning,
                  size: 30,
                ),
              ),
            ],
          ),
          Text(
            '${point.categoryLabel}${point.icao.isEmpty ? '' : ' · ${point.icao}'}',
            style: TextStyle(color: context.appSecondaryText),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _RangeMetric(
                  label: 'RANGE',
                  value: stale || range == null
                      ? '—'
                      : range.distanceNm.toStringAsFixed(1),
                  unit: 'NM',
                ),
              ),
              Expanded(
                child: _RangeMetric(
                  label: 'BEARING',
                  value: stale || range == null
                      ? '—'
                      : (range.bearingDeg.round() % 360).toString().padLeft(
                          3,
                          '0',
                        ),
                  unit: '°T',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
            style: TextStyle(color: context.appMutedText, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Direct great-circle distance from current GPS position. Not a route or navigation source; verify with current charts.',
            style: TextStyle(
              color: context.appFaintText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_PointFilter filter, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: context.appAccent,
      labelStyle: TextStyle(
        color: _filter == filter ? context.appBackground : context.appText,
        fontWeight: FontWeight.bold,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _pointRow(NavigationPoint point) {
    final selected = _selectedPoint?.id == point.id;
    final isFavourite = _favouriteIds.contains(point.id);
    final position = _locationStale ? null : _position;
    final range = position == null
        ? null
        : calculatePointRange(
            fromLatitude: position.latitude,
            fromLongitude: position.longitude,
            toLatitude: point.latitude,
            toLongitude: point.longitude,
          );
    return Card(
      color: selected ? context.appPanel : context.appCard,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.appAccent.withValues(alpha: selected ? 0.7 : 0.24),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: () {
          if (widget.selectForDistance) {
            final position = _position;
            if (position == null ||
                DateTime.now().difference(position.timestamp) >
                    const Duration(seconds: 10)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'A fresh GPS fix is needed to calculate distance.',
                  ),
                ),
              );
              return;
            }
            final range = calculatePointRange(
              fromLatitude: position.latitude,
              fromLongitude: position.longitude,
              toLatitude: point.latitude,
              toLongitude: point.longitude,
            );
            Navigator.of(context)
                .pop(PointSelection(point: point, range: range));
          } else {
            setState(() => _selectedPoint = point);
          }
        },
        leading: SizedBox(
          width: range == null ? 28 : 50,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (point.category) {
                  PointCategory.airfield => Icons.local_airport,
                  PointCategory.town => Icons.location_city,
                  PointCategory.port => Icons.directions_boat,
                  PointCategory.vrp => Icons.alt_route,
                },
                color: selected ? context.appAccent : context.appSecondaryText,
              ),
              if (range != null) ...[
                const SizedBox(width: 4),
                Transform.rotate(
                  angle: range.bearingDeg * math.pi / 180,
                  child: Icon(
                    Icons.navigation,
                    color: context.appAccent,
                    size: 18,
                    semanticLabel: 'Bearing to destination',
                  ),
                ),
              ],
            ],
          ),
        ),
        title: Text(
          point.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${point.categoryLabel}${point.icao.isEmpty ? '' : ' · ${point.icao}'} · ${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)}'
          '${range == null ? '' : ' · ${range.distanceNm.toStringAsFixed(1)} NM / ${range.bearingDeg.round() % 360}°T'}'
          '${point.details.isEmpty ? '' : '\n${point.details}'}',
          style: TextStyle(color: context.appMutedText, fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: isFavourite ? 'Remove favourite' : 'Add favourite',
          onPressed: () => unawaited(_toggleFavourite(point)),
          icon: Icon(
            isFavourite ? Icons.star : Icons.star_border,
            color: context.appWarning,
            size: 28,
          ),
        ),
      ),
    );
  }
}

List<NavigationPoint> _parseVrps(String csv) {
  final rows = _parseCsv(csv);
  if (rows.isEmpty) {
    throw const FormatException('VRP CSV is empty.');
  }
  final header = rows.first.map((cell) => cell.trim()).toList();
  final nameIndex = header.indexOf('VRP name');
  final latitudeIndex = header.indexOf('Latitude');
  final longitudeIndex = header.indexOf('Longitude');
  final aerodromeIndex = header.indexOf('Associated Aerodrome');
  final icaoIndex = header.indexOf('ICAO Code');
  final validFromIndex = header.indexOf('Valid From');
  if ([nameIndex, latitudeIndex, longitudeIndex, validFromIndex].contains(-1)) {
    throw const FormatException('VRP CSV is missing required columns.');
  }

  final points = <NavigationPoint>[];
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    final requiredIndex = [
      nameIndex,
      latitudeIndex,
      longitudeIndex,
      validFromIndex,
    ].reduce((a, b) => a > b ? a : b);
    if (row.length <= requiredIndex) {
      throw FormatException('VRP CSV row ${rowIndex + 1} has too few columns.');
    }
    final name = row[nameIndex].trim();
    final latitude = _parseCoordinate(row[latitudeIndex], isLatitude: true);
    final longitude = _parseCoordinate(row[longitudeIndex], isLatitude: false);
    final validFrom = row[validFromIndex].trim();
    final validDate = _parseDate(validFrom);
    if (name.isEmpty ||
        latitude == null ||
        longitude == null ||
        validDate == null) {
      throw FormatException(
        'VRP CSV row ${rowIndex + 1} has invalid name, coordinate, or valid-from date.',
      );
    }
    final aerodrome = aerodromeIndex >= 0 && row.length > aerodromeIndex
        ? row[aerodromeIndex].trim()
        : '';
    final icao = icaoIndex >= 0 && row.length > icaoIndex
        ? row[icaoIndex].trim()
        : '';
    points.add(
      NavigationPoint(
        id: 'vrp:${latitude.toStringAsFixed(5)}:${longitude.toStringAsFixed(5)}',
        name: name,
        category: PointCategory.vrp,
        latitude: latitude,
        longitude: longitude,
        icao: icao,
        details:
            '${aerodrome.isEmpty ? '' : '$aerodrome · '}Valid from $validFrom',
      ),
    );
  }
  return points;
}

List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quoted) {
      if (char == '"' && index + 1 < text.length && text[index + 1] == '"') {
        field.write('"');
        index++;
      } else if (char == '"') {
        quoted = false;
      } else {
        field.write(char);
      }
    } else if (char == '"' && field.isEmpty) {
      quoted = true;
    } else if (char == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (quoted) throw const FormatException('VRP CSV has an unterminated quote.');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

double? _parseCoordinate(String coordinate, {required bool isLatitude}) {
  final match = RegExp(r'^(\d{2,3})(\d{2})(\d{2}(?:\.\d+)?)([NSEW])$')
      .firstMatch(coordinate.trim().toUpperCase());
  if (match == null) return null;
  final degrees = int.tryParse(match.group(1)!);
  final minutes = int.tryParse(match.group(2)!);
  final seconds = double.tryParse(match.group(3)!);
  final hemisphere = match.group(4)!;
  if (degrees == null ||
      minutes == null ||
      seconds == null ||
      minutes >= 60 ||
      seconds >= 60 ||
      (isLatitude &&
          (degrees > 90 || hemisphere == 'E' || hemisphere == 'W')) ||
      (!isLatitude &&
          (degrees > 180 || hemisphere == 'N' || hemisphere == 'S'))) {
    return null;
  }
  final value = degrees + minutes / 60 + seconds / 3600;
  return hemisphere == 'S' || hemisphere == 'W' ? -value : value;
}

DateTime? _parseDate(String date) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(date);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

class _LargeSearchKeyboard extends StatefulWidget {
  const _LargeSearchKeyboard({
    required this.height,
    required this.initialValue,
    required this.onChanged,
    required this.onClose,
    required this.onSearch,
  });

  final double height;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final VoidCallback onSearch;

  @override
  State<_LargeSearchKeyboard> createState() => _LargeSearchKeyboardState();
}

class _LargeSearchKeyboardState extends State<_LargeSearchKeyboard> {
  late String _value = widget.initialValue;

  void _setValue(String value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  void _append(String key) {
    _setValue(_value + key);
  }

  void _backspace() {
    if (_value.isEmpty) return;
    _setValue(_value.substring(0, _value.length - 1));
  }

  Widget _keyRow(List<String> keys) => Row(
    children: [
      for (final key in keys)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => key == '⌫' ? _backspace() : _append(key),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: context.appPanel,
                  foregroundColor: context.appText,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('large-search-keyboard-panel'),
      width: double.infinity,
      height: widget.height,
      child: Material(
        color: context.appBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'LARGE SEARCH KEYBOARD',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close search keyboard',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.appPanel,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _value.isEmpty ? ' ' : _value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _keyRow('QWERTYUIOP'.split('')),
                  _keyRow('ASDFGHJKL'.split('')),
                  _keyRow(['Z', 'X', 'C', 'V', 'B', 'N', 'M', '⌫']),
                  _keyRow('1234567890'.split('')),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () => _append(' '),
                            child: const Text(
                              'SPACE',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () => _setValue(''),
                            child: const Text(
                              'CLEAR',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: widget.onSearch,
                            style: FilledButton.styleFrom(
                              backgroundColor: context.appAccent,
                              foregroundColor: context.appBackground,
                            ),
                            icon: const Icon(Icons.search),
                            label: const Text(
                              'SEARCH',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeMetric extends StatelessWidget {
  const _RangeMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.appMutedText, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '$value $unit',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _PointEditor extends StatefulWidget {
  const _PointEditor({this.initialCategory = PointCategory.vrp});

  final PointCategory initialCategory;

  @override
  State<_PointEditor> createState() => _PointEditorState();
}

class _PointEditorState extends State<_PointEditor> {
  final _name = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  late PointCategory _category = widget.initialCategory;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    if (name.isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      setState(() => _error = 'Enter a name and valid latitude / longitude.');
      return;
    }
    final id = 'custom:${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      NavigationPoint(
        id: id,
        name: name,
        category: _category,
        latitude: latitude,
        longitude: longitude,
        isCustom: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add custom point'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Point Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PointCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Point Type'),
              items: [
                for (final category in PointCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.name.toUpperCase()),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            _CoordinateField(
              controller: _latitude,
              label: 'Latitude',
              maxIntegerDigits: 2,
            ),
            const SizedBox(height: 10),
            _CoordinateField(
              controller: _longitude,
              label: 'Longitude',
              maxIntegerDigits: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('SAVE POINT'),
        ),
      ],
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.controller,
    required this.label,
    required this.maxIntegerDigits,
  });

  final TextEditingController controller;
  final String label;
  final int maxIntegerDigits;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      showCursor: false,
      onTap: () async {
        final value = await showDialog<String>(
          context: context,
          builder: (context) => _CoordinatePad(
            title: label,
            initialValue: controller.text,
            maxIntegerDigits: maxIntegerDigits,
          ),
        );
        if (value != null) controller.text = value;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Tap to enter',
        suffixIcon: const Icon(Icons.dialpad),
      ),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}

class _CoordinatePad extends StatefulWidget {
  const _CoordinatePad({
    required this.title,
    required this.initialValue,
    required this.maxIntegerDigits,
  });

  final String title;
  final String initialValue;
  final int maxIntegerDigits;

  @override
  State<_CoordinatePad> createState() => _CoordinatePadState();
}

class _CoordinatePadState extends State<_CoordinatePad> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _press(String key) {
    if (key == '⌫') {
      if (_value.isNotEmpty) {
        setState(() => _value = _value.substring(0, _value.length - 1));
      }
      return;
    }
    if (key == '±') {
      setState(
        () =>
            _value = _value.startsWith('-') ? _value.substring(1) : '-$_value',
      );
      return;
    }
    if (key == '.' && _value.contains('.')) return;
    final next = '$_value$key';
    final absolute = next.startsWith('-') ? next.substring(1) : next;
    final parts = absolute.split('.');
    if (parts.first.length > widget.maxIntegerDigits ||
        (parts.length > 1 && parts.last.length > 6)) {
      return;
    }
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '±',
      '0',
      '.',
      '⌫',
    ];
    return Dialog(
      backgroundColor: context.appBackground,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _value.isEmpty ? ' ' : _value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: keys.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                ),
                itemBuilder: (context, index) => FilledButton(
                  onPressed: () => _press(keys[index]),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.appPanel,
                    foregroundColor: context.appText,
                  ),
                  child: Text(
                    keys[index],
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _value = ''),
                      child: const Text('CLEAR'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _value),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.appAccent,
                        foregroundColor: context.appBackground,
                      ),
                      child: const Text('DONE'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
